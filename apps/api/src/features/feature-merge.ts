export function isPlainObject(v: any): v is Record<string, any> {
  return v !== null && typeof v === 'object' && !Array.isArray(v);
}

export function deepMerge(base: any, override: any): any {
  if (override === undefined) return base;
  if (override === null) return null;

  if (Array.isArray(base) && Array.isArray(override)) return override; // override arrays
  if (isPlainObject(base) && isPlainObject(override)) {
    const out: Record<string, any> = { ...base };
    for (const k of Object.keys(override)) {
      out[k] = deepMerge(base[k], override[k]);
    }
    return out;
  }
  return override;
}
