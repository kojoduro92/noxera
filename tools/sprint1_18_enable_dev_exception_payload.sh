#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MAIN="apps/api/src/main.ts"
FILTER="apps/api/src/common/filters/dev-http-exception.filter.ts"

mkdir -p "$(dirname "$FILTER")"

# backup main.ts
cp "$MAIN" "$MAIN.bak.$(date +%s)" || true

cat > "$FILTER" <<'EOF'
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
    // eslint-disable-next-line no-console
    console.error("❌ Unhandled error:", exception);

    res.status(status).json({
      statusCode: status,
      path: req.url,
      ...payload,
      stack: (exception as any)?.stack,
    });
  }
}
EOF

# Patch main.ts (import + useGlobalFilters) if not already wired
if ! grep -q "DevHttpExceptionFilter" "$MAIN"; then
  perl -0777 -i -pe 's/(from "\@nestjs\/core";\n)/$1import { DevHttpExceptionFilter } from ".\/common\/filters\/dev-http-exception.filter";\n/s' "$MAIN"
  perl -0777 -i -pe 's/(const app = await NestFactory\.create\([^\)]*\);\n)/$1\n  if (process.env.NODE_ENV !== "production") {\n    app.useGlobalFilters(new DevHttpExceptionFilter());\n  }\n/s' "$MAIN"
fi

echo "✅ DevHttpExceptionFilter added + wired in main.ts"
echo "NEXT:"
echo "  pnpm --filter api build"
echo "  pnpm --filter api dev"
