import { s3 }    from "./aws_clients.js";
import { config } from "./config.js";
import { ulid }   from "ulid";
import path       from "path";

export async function uploadImage(file) {
  const ext = path.extname(file.originalname).toLowerCase();
  const key = `${ulid()}${ext}`;

  await s3.upload({
    Bucket      : config.bucketName,
    Key         : key,
    Body        : file.buffer,
    ContentType : file.mimetype,
  }).promise();
}

export async function deleteImage(key) {
  await s3.deleteObject({
    Bucket: config.bucketName,
    Key   : key
  }).promise();
}

export async function listImages() {
  const out = await s3.listObjectsV2({
    Bucket: config.bucketName
  }).promise();
  return out.Contents.map(obj => obj.Key);
}