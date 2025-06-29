import AWS from "aws-sdk";
import { config } from "./config.js";

AWS.config.update({ region: config.region });
export const s3 = new AWS.S3();