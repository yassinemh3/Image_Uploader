import express from "express";
import multer from "multer";
import path from "path";
import { fileURLToPath } from "url";
import { uploadImage, listImages, deleteImage } from "./services.js";
import { config } from "./config.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname  = path.dirname(__filename);

const app    = express();
const upload = multer({ storage: multer.memoryStorage() });

app.set("view engine", "ejs");
app.set("views", path.join(__dirname, "templates"));
app.use(express.static(path.join(__dirname, "public")));

app.get("/", async (req, res) => {
  const images  = await listImages();
  const status  = req.query.status;      // uploaded | deleted | undefined
  res.render("index", {
    images,
    status,
    settings: { s3_bucket_name: config.bucketName }
  });
});

app.post("/upload", upload.single("file"), async (req, res) => {
  if (!req.file) return res.status(400).send("No file uploaded");
  await uploadImage(req.file);           // S3-Upload
  res.redirect("/prod/?status=uploaded");
});

app.post("/delete/:image_name", async (req, res) => {
  await deleteImage(req.params.image_name);
  res.redirect("/prod/?status=deleted");
});

export default app;