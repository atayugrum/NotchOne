// Daily totals only: no IP address, cookie or other identifier is stored.
export function count(context, name) {
  const store = context.env.COUNTS;
  if (!store) return;
  const key = `${name}:${new Date().toISOString().slice(0, 10)}`;
  context.waitUntil(
    store.get(key).then((value) => store.put(key, String(Number(value ?? 0) + 1))),
  );
}
