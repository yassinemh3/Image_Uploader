import { default as serverlessExpress } from "@vendia/serverless-express";
import app from "./app.js";

app.use((req, _res, next) => {
  console.log(
    `[${new Date().toISOString()}] ${req.method} ${req.originalUrl}`
  );
  next();
});

export const handler = serverlessExpress({ app });
