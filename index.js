import 'dotenv/config';
import express from "express";
import cors from "cors";
import multer from "multer";
import { nanoid } from "nanoid";
import path from "path";
import fs from "fs-extra";
import mongoose from "mongoose";

const PORT = Number(process.env.PORT) || 4000;       // ✅ sane default
const UPLOADS_DIR = path.join(process.cwd(), "uploads");
const PUBLIC_DIR = path.join(process.cwd(), "public"); // optional if you have a frontend

await fs.ensureDir(UPLOADS_DIR);

if (!process.env.MONGODB_URI) {
  console.error("Missing MONGODB_URI in .env");
  process.exit(1);
}
await mongoose.connect(process.env.MONGODB_URI);

const reportSchema = new mongoose.Schema(
  {
    id: { type: String, index: true },
    description: { type: String, default: "" },
    severity: { type: Number, default: null },
    reporter: { type: String, default: "" },
    image: { type: String, default: null },
    status: { type: String, default: "open" },
    comments: [{ text: String, at: Date }],
    location: {
      type: { type: String, enum: ["Point"], default: "Point" },
      coordinates: { type: [Number], default: [0, 0] }
    },
  },
  { timestamps: true }
);
reportSchema.index({ location: "2dsphere" });
const Report = mongoose.model("Report", reportSchema);

const app = express();
app.use(cors({ origin: "*" }));
app.use(express.json({ limit: "10mb" }));
app.use("/uploads", express.static(UPLOADS_DIR));

// (optional) serve your frontend from /public
app.use(express.static(PUBLIC_DIR));

app.get("/", (_req, res) => {
  res.send("FixMyRoad API is running");
});

const storage = multer.diskStorage({
  destination: (_, __, cb) => cb(null, UPLOADS_DIR),
  filename: (_, file, cb) => {
    const ext = path.extname(file.originalname || "");
    cb(null, `${Date.now()}-${nanoid(6)}${ext}`);
  },
});
const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 }
});

const nowISO = () => new Date().toISOString();

app.get("/health", (_req, res) => res.json({ ok: true, time: nowISO() }));

app.post("/reports", upload.single("image"), async (req, res) => {
  try {
    const { lat, lng, description = "", severity = null, reporter = "" } = req.body;
    if (lat == null || lng == null) return res.status(400).json({ error: "lat and lng are required" });

    const imagePath = req.file ? `/uploads/${req.file.filename}` : null;

    const doc = await Report.create({
      id: nanoid(10),
      description,
      severity: severity !== null ? Number(severity) : null,
      reporter,
      image: imagePath,
      status: "open",
      comments: [],
      location: { type: "Point", coordinates: [Number(lng), Number(lat)] },
    });

    res.status(201).json({ ok: true, report: doc });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "internal" });
  }
});

app.get("/reports", async (req, res) => {
  try {
    const p = Math.max(1, Number(req.query.page ?? 1));
    const l = Math.max(1, Math.min(100, Number(req.query.limit ?? 50)));
    const total = await Report.countDocuments();
    const reports = await Report.find({})
      .sort({ createdAt: -1 })
      .skip((p - 1) * l)
      .limit(l)
      .lean();
    res.json({ ok: true, total, page: p, limit: l, reports });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "internal" });
  }
});

app.get("/reports/:id", async (req, res) => {
  const r = await Report.findOne({ id: req.params.id }).lean();
  if (!r) return res.status(404).json({ error: "not_found" });
  res.json({ ok: true, report: r });
});

app.put("/reports/:id", async (req, res) => {
  try {
    const r = await Report.findOne({ id: req.params.id });
    if (!r) return res.status(404).json({ error: "not_found" });

    if (req.body.status) r.status = req.body.status;
    if (req.body.severity !== undefined) r.severity = Number(req.body.severity);
    if (req.body.comment) r.comments.push({ text: req.body.comment, at: new Date() });

    await r.save();
    res.json({ ok: true, report: r });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "internal" });
  }
});

app.delete("/reports/:id", async (req, res) => {
  try {
    const r = await Report.findOneAndDelete({ id: req.params.id });
    if (!r) return res.status(404).json({ error: "not_found" });

    if (r.image) {
      // ✅ delete from uploads safely regardless of leading slash
      const imgPath = path.join(UPLOADS_DIR, path.basename(r.image));
      await fs.remove(imgPath).catch(() => {});
    }
    res.json({ ok: true });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "internal" });
  }
});

app.get("/near", async (req, res) => {
  try {
    const { lat, lng, radius = 200 } = req.query;
    if (lat == null || lng == null) return res.status(400).json({ error: "lat and lng are required" });

    const docs = await Report.find({
      location: {
        $near: {
          $geometry: { type: "Point", coordinates: [Number(lng), Number(lat)] },
          $maxDistance: Number(radius)
        }
      }
    }).lean();

    res.json({ ok: true, total: docs.length, reports: docs });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "internal" });
  }
});

app.get("/stats", async (_req, res) => {
  const [total, open, inProgress, fixed] = await Promise.all([
    Report.countDocuments(),
    Report.countDocuments({ status: "open" }),
    Report.countDocuments({ status: "in_progress" }),
    Report.countDocuments({ status: "fixed" }),
  ]);
  res.json({ ok: true, total, open, inProgress, fixed });
});

// ✅ robust server start with fallback if port is busy
function start(port) {
  const server = app.listen(port, () => {
    const addr = server.address();
    const actualPort = typeof addr === "object" && addr ? addr.port : port;
    console.log(`Server running on http://localhost:${actualPort}`);
  });
  server.on("error", (err) => {
    if (err.code === "EADDRINUSE") {
      console.warn(`Port ${port} in use, trying ${port + 1}...`);
      start(port + 1);
    } else if (err.code === "EACCES") {
      console.warn(`No permission on port ${port}, trying ${port + 1}...`);
      start(port + 1);
    } else {
      console.error(err);
      process.exit(1);
    }
  });
}
start(PORT);
