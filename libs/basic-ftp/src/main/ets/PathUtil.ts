/*
 * Copyright (C) 2023 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

const nodeInternalPrefix = "__node_internal_";
const constants = {
  // Alphabet chars.
  CHAR_UPPERCASE_A: 65 /* A */
,
  CHAR_LOWERCASE_A: 97 /* a */
,
  CHAR_UPPERCASE_Z: 90 /* Z */
,
  CHAR_LOWERCASE_Z: 122 /* z */
,
  CHAR_UPPERCASE_C: 67 /* C */
,
  CHAR_LOWERCASE_B: 98 /* b */
,
  CHAR_LOWERCASE_E: 101 /* e */
,
  CHAR_LOWERCASE_N: 110 /* n */
,

  // Non-alphabetic chars.
  CHAR_DOT: 46 /* . */
,
  CHAR_FORWARD_SLASH: 47 /* / */
,
  CHAR_BACKWARD_SLASH: 92 /* \ */
,
  CHAR_VERTICAL_LINE: 124 /* | */
,
  CHAR_COLON: 58 /* : */
,
  CHAR_QUESTION_MARK: 63 /* ? */
,
  CHAR_UNDERSCORE: 95 /* _ */
,
  CHAR_LINE_FEED: 10 /* \n */
,
  CHAR_CARRIAGE_RETURN: 13 /* \r */
,
  CHAR_TAB: 9 /* \t */
,
  CHAR_FORM_FEED: 12 /* \f */
,
  CHAR_EXCLAMATION_MARK: 33 /* ! */
,
  CHAR_HASH: 35 /* # */
,
  CHAR_SPACE: 32 /*   */
,
  CHAR_NO_BREAK_SPACE: 160 /* \u00A0 */
,
  CHAR_ZERO_WIDTH_NOBREAK_SPACE: 65279 /* \uFEFF */
,
  CHAR_LEFT_SQUARE_BRACKET: 91, //* [ */
  CHAR_RIGHT_SQUARE_BRACKET: 93 /* ] */
,
  CHAR_LEFT_ANGLE_BRACKET: 60 /* < */
,
  CHAR_RIGHT_ANGLE_BRACKET: 62 /* > */
,
  CHAR_LEFT_CURLY_BRACKET: 123 /* { */
,
  CHAR_RIGHT_CURLY_BRACKET: 125 /* } */
,
  CHAR_HYPHEN_MINUS: 45 /* - */
,
  CHAR_PLUS: 43 /* + */
,
  CHAR_DOUBLE_QUOTE: 34 /* " */
,
  CHAR_SINGLE_QUOTE: 39 /* ' */
,
  CHAR_PERCENT: 37 /* % */
,
  CHAR_SEMICOLON: 59 /* ; */
,
  CHAR_CIRCUMFLEX_ACCENT: 94 /* ^ */
,
  CHAR_GRAVE_ACCENT: 96 /* ` */
,
  CHAR_AT: 64 /* @ */
,
  CHAR_AMPERSAND: 38 /* & */
,
  CHAR_EQUAL: 61 /* = */
,

  // Digits
  CHAR_0: 48 /* 0 */
,
  CHAR_9: 57 /* 9 */
,

  EOL: "\n",
};

function isPathSeparator(code) {
  return code === constants.CHAR_FORWARD_SLASH;
}

function ObjectDefineProperty(self, name, prop) {
  return Object.defineProperty(self, name, prop);
}

function StringPrototypeCharCodeAt(value, index) {
  return value.charCodeAt(index);
}

function hideStackFrames(fn) {
  // We rename the functions that will be hidden to cut off the stacktrace
  // at the outermost one
  const hidden = nodeInternalPrefix + fn.name;
  ObjectDefineProperty(fn, "name", {
    __proto__: null, value: hidden
  });
  return fn;
};

function StringPrototypeLastIndexOf(value, separator) {
  return value.lastIndexOf(separator);
}

function validateString(value, name) {
  hideStackFrames(() => {
    if (typeof value !== "string") {
      throw new Error("ERR_INVALID_ARG_TYPE value:" + value + " name:" + name);
    }
  });
}

function StringPrototypeSlice(self, start, end) {
  return self.slice(start, end);
}

function join(...args) {
  if (args.length === 0) return ".";
  let joined;
  for (let i = 0; i < args.length; ++i) {
    const arg = args[i];
    validateString(arg, "path");
    if (arg.length > 0) {
      if (joined === undefined) joined = arg;
      else joined += `/${arg}`;
    }
  }
  if (joined === undefined) return ".";
  return normalize(joined);
}

function normalize(path) {
  validateString(path, "path");

  if (path.length === 0) return ".";

  const isAbsolute =
    StringPrototypeCharCodeAt(path, 0) === constants.CHAR_FORWARD_SLASH;
  const trailingSeparator =
    StringPrototypeCharCodeAt(path, path.length - 1) ===
    constants.CHAR_FORWARD_SLASH;

  // Normalize the path
  path = normalizeString(path,!isAbsolute, "/");

  if (path.length === 0) {
    if (isAbsolute) return "/";
    return trailingSeparator ? "./" : ".";
  }
  if (trailingSeparator) path += "/";

  return isAbsolute ? `/${path}` : path;
}

function normalizeString(path, allowAboveRoot, separator) {
  let res = "";
  let lastSegmentLength = 0;
  let lastSlash = -1;
  let dots = 0;
  let code = 0;
  for (let i = 0; i <= path.length; ++i) {
    if (i < path.length) code = StringPrototypeCharCodeAt(path, i);
    else if (isPathSeparator(code)) break;
    else code = constants.CHAR_FORWARD_SLASH;

    if (isPathSeparator(code)) {
      if (lastSlash === i - 1 || dots === 1) {
      } else if (dots === 2) {
        if (
          res.length < 2 ||
          lastSegmentLength !== 2 ||
          StringPrototypeCharCodeAt(res, res.length - 1) !==
          constants.CHAR_DOT ||
          StringPrototypeCharCodeAt(res, res.length - 2) !== constants.CHAR_DOT
        ) {
          if (res.length > 2) {
            const lastSlashIndex = StringPrototypeLastIndexOf(res, separator);
            if (lastSlashIndex === -1) {
              res = "";
              lastSegmentLength = 0;
            } else {
              res = StringPrototypeSlice(res, 0, lastSlashIndex);
              lastSegmentLength =
              res.length - 1 - StringPrototypeLastIndexOf(res, separator);
            }
            lastSlash = i;
            dots = 0;
            continue;
          } else if (res.length !== 0) {
            res = "";
            lastSegmentLength = 0;
            lastSlash = i;
            dots = 0;
            continue;
          }
        }
        if (allowAboveRoot) {
          res += res.length > 0 ? `${separator}..` : "..";
          lastSegmentLength = 2;
        }
      } else {
        if (res.length > 0)
          res += `${separator}${StringPrototypeSlice(path, lastSlash + 1, i)}`;
        else res = StringPrototypeSlice(path, lastSlash + 1, i);
        lastSegmentLength = i - lastSlash - 1;
      }
      lastSlash = i;
      dots = 0;
    } else if (code === constants.CHAR_DOT && dots !== -1) {
      ++dots;
    } else {
      dots = -1;
    }
  }
  return res;
}

/**
 * @param { Promise } promise
 * @param { Object= } errorExt - Additional Information you can pass to the err object
 * @return { Promise }
 */
function to<T, U = Error>(
    promise: Promise<T>,
    errorExt?: object
): Promise<[U, undefined] | [null, T]> {
  return promise
    .then<[null, T]>((data: T) => [null, data])
    .catch<[U, undefined]>((err: U) => {
      if (errorExt) {
        const parsedError = Object.assign({}, err, errorExt);
        return [parsedError, undefined];
      }

      return [err, undefined];
    });
}

export { join, to }