import { ProtectedValue } from "../crypto/protected-value";

declare global {
  interface Node {
    protectedValue: ProtectedValue | undefined;
    lineNumber: number | undefined;
  }
}