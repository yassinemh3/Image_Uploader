// handler.js  –  Einstieg für AWS Lambda
import { default as serverlessExpress } from "@vendia/serverless-express";
import app from "./app.js";

/* ---------- 1. Express-Middleware für Request-Logs ---------- */
app.use((req, _res, next) => {
  console.log(
    `[${new Date().toISOString()}] ${req.method} ${req.originalUrl}`
  );
  next();
});

/* ---------- 2. Lambda-Wrapper mit Event-/Context-Log ---------- */
export const handler = serverlessExpress({ app });

/* export const handler = async (event, context) => {
  console.log("Lambda event →", JSON.stringify(event));
  console.log("Lambda context →", JSON.stringify({
    requestId: context.awsRequestId,
    functionName: context.functionName,
    invokedFunctionArn: context.invokedFunctionArn
  }));
  // delegieren an serverless-http
  return await serverlessHandler(event, context);
};*/