#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MAIN="apps/api/src/main.ts"
FILTER="apps/api/src/common/filters/dev-http-exception.filter.ts"

mkdir -p "$(dirname "$FILTER")"

# Ensure filter file exists (rewrite if missing)
if [ ! -f "$FILTER" ]; then
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
fi

# Backup main.ts
cp "$MAIN" "$MAIN.bak.$(date +%s)" || true

# Ensure main.ts imports the filter (Prisma/Nest compile error fix)
if ! grep -q 'dev-http-exception.filter' "$MAIN"; then
  perl -0777 -i -pe 's/^/import { DevHttpExceptionFilter } from ".\/common\/filters\/dev-http-exception.filter";\n/s' "$MAIN"
fi

echo "✅ Fixed: DevHttpExceptionFilter import added to main.ts"
echo "NEXT:"
echo "  pnpm --filter api build"
echo "  pnpm --filter api dev"
