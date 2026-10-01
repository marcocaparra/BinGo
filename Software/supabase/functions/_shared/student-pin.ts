// Compatible with the existing FastAPI PBKDF2-HMAC-SHA256 salt$digest format.
// Kept separate so machine-auth and deployed health/deposit code stay intact.
export async function verifyStudentPin(
  pin: string,
  hash: string,
): Promise<boolean> {
  if (!/^[0-9]{4}$/.test(pin)) return false;
  const parts = hash.split("$");
  const base64 =
    /^(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?$/;
  if (parts.length !== 2 || parts.some((part) => !part || !base64.test(part))) {
    return false;
  }
  try {
    const salt = Uint8Array.from(atob(parts[0]), (ch) => ch.charCodeAt(0));
    const expected = Uint8Array.from(atob(parts[1]), (ch) => ch.charCodeAt(0));
    if (!salt.length || expected.length !== 32) return false;
    const key = await crypto.subtle.importKey(
      "raw",
      new TextEncoder().encode(pin),
      "PBKDF2",
      false,
      ["deriveBits"],
    );
    const digest = new Uint8Array(
      await crypto.subtle.deriveBits(
        {
          name: "PBKDF2",
          hash: "SHA-256",
          salt,
          iterations: 120_000,
        },
        key,
        256,
      ),
    );
    let difference = 0;
    for (let i = 0; i < expected.length; i++) {
      difference |= digest[i] ^ expected[i];
    }
    return difference === 0;
  } catch {
    return false;
  }
}
