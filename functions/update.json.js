import { count } from "./_counter.js";

// The app checks at most once a day, so this total is close to the number of active installs.
export async function onRequestGet(context) {
  count(context, "check");
  return context.env.ASSETS.fetch(context.request);
}
