import { ProtectedValue } from "../crypto/protected-value";

declare module '@xmldom/xmldom' {
  /**
   * The DOM implementation.
   */
  interface Node {
    protectedValue: ProtectedValue | undefined;
  }
}