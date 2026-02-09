import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
} from "@nestjs/common";

@Catch()
export class DevHttpExceptionFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const res = ctx.getResponse<any>();
    const req = ctx.getRequest<any>();

    const status =
      exception instanceof HttpException
        ? exception.getStatus()
        : HttpStatus.INTERNAL_SERVER_ERROR;

    const base =
      exception instanceof HttpException
        ? exception.getResponse()
        : { message: (exception as any)?.message ?? "Internal server error" };

    const payload = typeof base === "string" ? { message: base } : (base as any);

    // Always log server-side
     
    console.error("❌ Unhandled error:", exception);

    res.status(status).json({
      statusCode: status,
      path: req.url,
      ...payload,
      stack: (exception as any)?.stack,
    });
  }
}
