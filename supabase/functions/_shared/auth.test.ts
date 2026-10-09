import { UUID_RE } from "./auth.ts";

Deno.test("UUID_RE accepts the canonical seed id", () => {
  if (!UUID_RE.test("22222222-2222-2222-2222-222222222222")) {
    throw new Error("canonical seed UUID was rejected");
  }
});

Deno.test("UUID_RE rejects malformed ids", () => {
  const invalid = [
    "invalido",
    "2222",
    " 22222222-2222-2222-2222-222222222222",
    "22222222-2222-2222-2222-222222222222x",
  ];
  if (invalid.some((value) => UUID_RE.test(value))) {
    throw new Error("malformed UUID was accepted");
  }
});
