#!/bin/bash
set -e

cd /home/jackson-core
git reset --hard
bash /home/check_git_changes.sh
git checkout ac6d8e22847c19b2695cbd7d1f418e07a9a3dbb2

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/com/fasterxml/jackson/core/base/ParserBase.java b/src/main/java/com/fasterxml/jackson/core/base/ParserBase.java
index 7c97e2a6..7341d2e5 100644
--- a/src/main/java/com/fasterxml/jackson/core/base/ParserBase.java
+++ b/src/main/java/com/fasterxml/jackson/core/base/ParserBase.java
@@ -11,7 +11,7 @@ import com.fasterxml.jackson.core.json.DupDetector;
 import com.fasterxml.jackson.core.json.JsonReadContext;
 import com.fasterxml.jackson.core.json.PackageVersion;
 import com.fasterxml.jackson.core.util.ByteArrayBuilder;
-import com.fasterxml.jackson.core.util.TextBuffer;
+import com.fasterxml.jackson.core.util.SegmentedTextBuffer;
 
 /**
  * Intermediate base class used by all Jackson {@link JsonParser}
@@ -140,7 +140,7 @@ public abstract class ParserBase extends ParserMinimalBase
      * field names if necessary (name split across boundary,
      * contains escape sequence, or access needed to char array)
      */
-    protected final TextBuffer _textBuffer;
+    protected final SegmentedTextBuffer _textBuffer;
 
     /**
      * Temporary buffer that is needed if field name is accessed
@@ -482,7 +482,7 @@ public abstract class ParserBase extends ParserMinimalBase
      * separately (if need be).
      */
     protected void _releaseBuffers() throws IOException {
-        _textBuffer.releaseBuffers();
+        _textBuffer.releaseCharBuffers();
         char[] buf = _nameCopyBuffer;
         if (buf != null) {
             _nameCopyBuffer = null;
@@ -575,7 +575,7 @@ public abstract class ParserBase extends ParserMinimalBase
     
     protected final JsonToken resetAsNaN(String valueStr, double value)
     {
-        _textBuffer.resetWithString(valueStr);
+        _textBuffer.resetToString(valueStr);
         _numberDouble = value;
         _numTypesValid = NR_DOUBLE;
         return JsonToken.VALUE_NUMBER_FLOAT;
@@ -841,22 +841,22 @@ public abstract class ParserBase extends ParserMinimalBase
          */
         try {
             if (expType == NR_BIGDECIMAL) {
-                _numberBigDecimal = _textBuffer.contentsAsDecimal();
+                _numberBigDecimal = _textBuffer.contentsAsBigDecimal();
                 _numTypesValid = NR_BIGDECIMAL;
             } else {
                 // Otherwise double has to do
-                _numberDouble = _textBuffer.contentsAsDouble();
+                _numberDouble = _textBuffer.getContentsAsDouble();
                 _numTypesValid = NR_DOUBLE;
             }
         } catch (NumberFormatException nex) {
             // Can this ever occur? Due to overflow, maybe?
-            _wrapError("Malformed numeric value '"+_textBuffer.contentsAsString()+"'", nex);
+            _wrapError("Malformed numeric value '"+_textBuffer.getContentsAsString()+"'", nex);
         }
     }
     
     private void _parseSlowInt(int expType, char[] buf, int offset, int len) throws IOException
     {
-        String numStr = _textBuffer.contentsAsString();
+        String numStr = _textBuffer.getContentsAsString();
         try {
             // [JACKSON-230] Some long cases still...
             if (NumberInput.inLongRange(buf, offset, len, _numberNegative)) {
diff --git a/src/main/java/com/fasterxml/jackson/core/io/IOContext.java b/src/main/java/com/fasterxml/jackson/core/io/IOContext.java
index 84fefc12..2e71c36b 100644
--- a/src/main/java/com/fasterxml/jackson/core/io/IOContext.java
+++ b/src/main/java/com/fasterxml/jackson/core/io/IOContext.java
@@ -2,7 +2,7 @@ package com.fasterxml.jackson.core.io;
 
 import com.fasterxml.jackson.core.JsonEncoding;
 import com.fasterxml.jackson.core.util.BufferRecycler;
-import com.fasterxml.jackson.core.util.TextBuffer;
+import com.fasterxml.jackson.core.util.SegmentedTextBuffer;
 
 /**
  * To limit number of configuration and state objects to pass, all
@@ -133,8 +133,8 @@ public class IOContext
     /**********************************************************
      */
 
-    public TextBuffer constructTextBuffer() {
-        return new TextBuffer(_bufferRecycler);
+    public SegmentedTextBuffer constructTextBuffer() {
+        return new SegmentedTextBuffer(_bufferRecycler);
     }
 
     /**
diff --git a/src/main/java/com/fasterxml/jackson/core/io/JsonStringEncoder.java b/src/main/java/com/fasterxml/jackson/core/io/JsonStringEncoder.java
index 07956ebb..d77c1c92 100644
--- a/src/main/java/com/fasterxml/jackson/core/io/JsonStringEncoder.java
+++ b/src/main/java/com/fasterxml/jackson/core/io/JsonStringEncoder.java
@@ -4,7 +4,7 @@ import java.lang.ref.SoftReference;
 
 import com.fasterxml.jackson.core.util.BufferRecycler;
 import com.fasterxml.jackson.core.util.ByteArrayBuilder;
-import com.fasterxml.jackson.core.util.TextBuffer;
+import com.fasterxml.jackson.core.util.SegmentedTextBuffer;
 
 /**
  * Helper class used for efficient encoding of JSON String values (including
@@ -41,7 +41,7 @@ public final class JsonStringEncoder
      * Lazily constructed text buffer used to produce JSON encoded Strings
      * as characters (without UTF-8 encoding)
      */
-    protected TextBuffer _text;
+    protected SegmentedTextBuffer _text;
 
     /**
      * Lazily-constructed builder used for UTF-8 encoding of text values
@@ -94,12 +94,12 @@ public final class JsonStringEncoder
      */
     public char[] quoteAsString(String input)
     {
-        TextBuffer textBuffer = _text;
+        SegmentedTextBuffer textBuffer = _text;
         if (textBuffer == null) {
             // no allocator; can add if we must, shouldn't need to
-            _text = textBuffer = new TextBuffer(null);
+            _text = textBuffer = new SegmentedTextBuffer(null);
         }
-        char[] outputBuffer = textBuffer.emptyAndGetCurrentSegment();
+        char[] outputBuffer = textBuffer.clearAndGetCurrentSegment();
         final int[] escCodes = CharTypes.get7BitOutputEscapes();
         final int escCodeCount = escCodes.length;
         int inPtr = 0;
@@ -115,7 +115,7 @@ public final class JsonStringEncoder
                     break tight_loop;
                 }
                 if (outPtr >= outputBuffer.length) {
-                    outputBuffer = textBuffer.finishCurrentSegment();
+                    outputBuffer = textBuffer.completeCurrentSegment();
                     outPtr = 0;
                 }
                 outputBuffer[outPtr++] = c;
@@ -135,7 +135,7 @@ public final class JsonStringEncoder
                 if (first > 0) {
                     System.arraycopy(_qbuf, 0, outputBuffer, outPtr, first);
                 }
-                outputBuffer = textBuffer.finishCurrentSegment();
+                outputBuffer = textBuffer.completeCurrentSegment();
                 int second = length - first;
                 System.arraycopy(_qbuf, first, outputBuffer, 0, second);
                 outPtr = second;
@@ -145,7 +145,7 @@ public final class JsonStringEncoder
             }
         }
         textBuffer.setCurrentLength(outPtr);
-        return textBuffer.contentsAsArray();
+        return textBuffer.contentsAsCharArray();
     }
 
     /**
diff --git a/src/main/java/com/fasterxml/jackson/core/io/SegmentedStringWriter.java b/src/main/java/com/fasterxml/jackson/core/io/SegmentedStringWriter.java
index 00b52c6f..66f9ab37 100644
--- a/src/main/java/com/fasterxml/jackson/core/io/SegmentedStringWriter.java
+++ b/src/main/java/com/fasterxml/jackson/core/io/SegmentedStringWriter.java
@@ -3,7 +3,7 @@ package com.fasterxml.jackson.core.io;
 import java.io.*;
 
 import com.fasterxml.jackson.core.util.BufferRecycler;
-import com.fasterxml.jackson.core.util.TextBuffer;
+import com.fasterxml.jackson.core.util.SegmentedTextBuffer;
 
 /**
  * Efficient alternative to {@link StringWriter}, based on using segmented
@@ -15,11 +15,11 @@ import com.fasterxml.jackson.core.util.TextBuffer;
  */
 public final class SegmentedStringWriter extends Writer
 {
-    final protected TextBuffer _buffer;
+    final protected SegmentedTextBuffer _buffer;
 
     public SegmentedStringWriter(BufferRecycler br) {
         super();
-        _buffer = new TextBuffer(br);
+        _buffer = new SegmentedTextBuffer(br);
     }
 
     /*
@@ -52,19 +52,19 @@ public final class SegmentedStringWriter extends Writer
     @Override public void flush() { } // NOP
 
     @Override
-    public void write(char[] cbuf) { _buffer.append(cbuf, 0, cbuf.length); }
+    public void write(char[] cbuf) { _buffer.appendChar(cbuf, 0, cbuf.length); }
 
     @Override
-    public void write(char[] cbuf, int off, int len) { _buffer.append(cbuf, off, len); }
+    public void write(char[] cbuf, int off, int len) { _buffer.appendChar(cbuf, off, len); }
 
     @Override
-    public void write(int c) { _buffer.append((char) c); }
+    public void write(int c) { _buffer.appendChar((char) c); }
 
     @Override
     public void write(String str) { _buffer.append(str, 0, str.length()); }
 
     @Override
-    public void write(String str, int off, int len) { _buffer.append(str, off, len); }
+    public void write(String str, int off, int len) { _buffer.appendChar(str, off, len); }
 
     /*
     /**********************************************************
@@ -80,8 +80,8 @@ public final class SegmentedStringWriter extends Writer
      * will just return an empty String.
      */
     public String getAndClear() {
-        String result = _buffer.contentsAsString();
-        _buffer.releaseBuffers();
+        String result = _buffer.getContentsAsString();
+        _buffer.releaseCharBuffers();
         return result;
     }
 }
diff --git a/src/main/java/com/fasterxml/jackson/core/json/ReaderBasedJsonParser.java b/src/main/java/com/fasterxml/jackson/core/json/ReaderBasedJsonParser.java
index b5b0051c..b2f5091b 100644
--- a/src/main/java/com/fasterxml/jackson/core/json/ReaderBasedJsonParser.java
+++ b/src/main/java/com/fasterxml/jackson/core/json/ReaderBasedJsonParser.java
@@ -232,7 +232,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
                 _tokenIncomplete = false;
                 _finishString(); // only strings can be incomplete
             }
-            return _textBuffer.contentsAsString();
+            return _textBuffer.getContentsAsString();
         }
         return _getText2(t);
     }
@@ -248,7 +248,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
                 _tokenIncomplete = false;
                 _finishString(); // only strings can be incomplete
             }
-            return _textBuffer.contentsAsString();
+            return _textBuffer.getContentsAsString();
         }
         return super.getValueAsString(null);
     }
@@ -261,7 +261,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
                 _tokenIncomplete = false;
                 _finishString(); // only strings can be incomplete
             }
-            return _textBuffer.contentsAsString();
+            return _textBuffer.getContentsAsString();
         }
         return super.getValueAsString(defValue);
     }
@@ -278,7 +278,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
             // fall through
         case ID_NUMBER_INT:
         case ID_NUMBER_FLOAT:
-            return _textBuffer.contentsAsString();
+            return _textBuffer.getContentsAsString();
         default:
             return t.asString();
         }
@@ -336,7 +336,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
                 // fall through
             case ID_NUMBER_INT:
             case ID_NUMBER_FLOAT:
-                return _textBuffer.size();
+                return _textBuffer.length();
                 
             default:
                 return _currToken.asCharArray().length;
@@ -726,7 +726,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
                     _tokenIncomplete = false;
                     _finishString();
                 }
-                return _textBuffer.contentsAsString();
+                return _textBuffer.getContentsAsString();
             }
             if (t == JsonToken.START_ARRAY) {
                 _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
@@ -886,7 +886,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
             _verifyRootSpace(ch);
         }
         int len = ptr-startPtr;
-        _textBuffer.resetWithShared(_inputBuffer, startPtr, len);
+        _textBuffer.resetWithSharedBuffer(_inputBuffer, startPtr, len);
         return resetInt(false, intLen);
     }
 
@@ -949,7 +949,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
             _verifyRootSpace(ch);
         }
         int len = ptr-startPtr;
-        _textBuffer.resetWithShared(_inputBuffer, startPtr, len);
+        _textBuffer.resetWithSharedBuffer(_inputBuffer, startPtr, len);
         // And there we have it!
         return resetFloat(neg, intLen, fractLen, expLen);
     }
@@ -998,7 +998,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
             _verifyRootSpace(ch);
         }
         int len = ptr-startPtr;
-        _textBuffer.resetWithShared(_inputBuffer, startPtr, len);
+        _textBuffer.resetWithSharedBuffer(_inputBuffer, startPtr, len);
         return resetInt(true, intLen);
     }
 
@@ -1012,7 +1012,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
     private final JsonToken _parseNumber2(boolean neg, int startPtr) throws IOException
     {
         _inputPtr = neg ? (startPtr+1) : startPtr;
-        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
+        char[] outBuf = _textBuffer.clearAndGetCurrentSegment();
         int outPtr = 0;
 
         // Need to prepend sign?
@@ -1033,7 +1033,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
         while (c >= '0' && c <= '9') {
             ++intLen;
             if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
+                outBuf = _textBuffer.completeCurrentSegment();
                 outPtr = 0;
             }
             outBuf[outPtr++] = c;
@@ -1067,7 +1067,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
                 }
                 ++fractLen;
                 if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
+                    outBuf = _textBuffer.completeCurrentSegment();
                     outPtr = 0;
                 }
                 outBuf[outPtr++] = c;
@@ -1081,7 +1081,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
         int expLen = 0;
         if (c == 'e' || c == 'E') { // exponent?
             if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
+                outBuf = _textBuffer.completeCurrentSegment();
                 outPtr = 0;
             }
             outBuf[outPtr++] = c;
@@ -1091,7 +1091,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
             // Sign indicator?
             if (c == '-' || c == '+') {
                 if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
+                    outBuf = _textBuffer.completeCurrentSegment();
                     outPtr = 0;
                 }
                 outBuf[outPtr++] = c;
@@ -1104,7 +1104,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
             while (c <= INT_9 && c >= INT_0) {
                 ++expLen;
                 if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
+                    outBuf = _textBuffer.completeCurrentSegment();
                     outPtr = 0;
                 }
                 outBuf[outPtr++] = c;
@@ -1270,7 +1270,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
 
     private String _parseName2(int startPtr, int hash, int endChar) throws IOException
     {
-        _textBuffer.resetWithShared(_inputBuffer, startPtr, (_inputPtr - startPtr));
+        _textBuffer.resetWithSharedBuffer(_inputBuffer, startPtr, (_inputPtr - startPtr));
 
         /* Output pointers; calls will also ensure that the buffer is
          * not shared and has room for at least one more char.
@@ -1308,16 +1308,16 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
 
             // Need more room?
             if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
+                outBuf = _textBuffer.completeCurrentSegment();
                 outPtr = 0;
             }
         }
         _textBuffer.setCurrentLength(outPtr);
         {
-            TextBuffer tb = _textBuffer;
+            SegmentedTextBuffer tb = _textBuffer;
             char[] buf = tb.getTextBuffer();
             int start = tb.getTextOffset();
-            int len = tb.size();
+            int len = tb.length();
 
             return _symbols.findSymbol(buf, start, len, hash);
         }
@@ -1465,7 +1465,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
     
     protected JsonToken _handleApos() throws IOException
     {
-        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
+        char[] outBuf = _textBuffer.clearAndGetCurrentSegment();
         int outPtr = _textBuffer.getCurrentSegmentSize();
 
         while (true) {
@@ -1494,7 +1494,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
             }
             // Need more room?
             if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
+                outBuf = _textBuffer.completeCurrentSegment();
                 outPtr = 0;
             }
             // Ok, let's add char to output:
@@ -1506,7 +1506,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
     
     private String _handleOddName2(int startPtr, int hash, int[] codes) throws IOException
     {
-        _textBuffer.resetWithShared(_inputBuffer, startPtr, (_inputPtr - startPtr));
+        _textBuffer.resetWithSharedBuffer(_inputBuffer, startPtr, (_inputPtr - startPtr));
         char[] outBuf = _textBuffer.getCurrentSegment();
         int outPtr = _textBuffer.getCurrentSegmentSize();
         final int maxCode = codes.length;
@@ -1533,16 +1533,16 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
 
             // Need more room?
             if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
+                outBuf = _textBuffer.completeCurrentSegment();
                 outPtr = 0;
             }
         }
         _textBuffer.setCurrentLength(outPtr);
         {
-            TextBuffer tb = _textBuffer;
+            SegmentedTextBuffer tb = _textBuffer;
             char[] buf = tb.getTextBuffer();
             int start = tb.getTextOffset();
-            int len = tb.size();
+            int len = tb.length();
 
             return _symbols.findSymbol(buf, start, len, hash);
         }
@@ -1566,7 +1566,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
                 int ch = _inputBuffer[ptr];
                 if (ch < maxCode && codes[ch] != 0) {
                     if (ch == '"') {
-                        _textBuffer.resetWithShared(_inputBuffer, _inputPtr, (ptr-_inputPtr));
+                        _textBuffer.resetWithSharedBuffer(_inputBuffer, _inputPtr, (ptr-_inputPtr));
                         _inputPtr = ptr+1;
                         // Yes, we got it all
                         return;
@@ -1580,7 +1580,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
         /* Either ran out of input, or bumped into an escape
          * sequence...
          */
-        _textBuffer.resetWithCopy(_inputBuffer, _inputPtr, (ptr-_inputPtr));
+        _textBuffer.resetAndCopy(_inputBuffer, _inputPtr, (ptr-_inputPtr));
         _inputPtr = ptr;
         _finishString2();
     }
@@ -1615,7 +1615,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
             }
             // Need more room?
             if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
+                outBuf = _textBuffer.completeCurrentSegment();
                 outPtr = 0;
             }
             // Ok, let's add char to output:
diff --git a/src/main/java/com/fasterxml/jackson/core/json/UTF8StreamJsonParser.java b/src/main/java/com/fasterxml/jackson/core/json/UTF8StreamJsonParser.java
index d25ae636..b763fd52 100644
--- a/src/main/java/com/fasterxml/jackson/core/json/UTF8StreamJsonParser.java
+++ b/src/main/java/com/fasterxml/jackson/core/json/UTF8StreamJsonParser.java
@@ -284,7 +284,7 @@ public class UTF8StreamJsonParser
                 _tokenIncomplete = false;
                 return _finishAndReturnString(); // only strings can be incomplete
             }
-            return _textBuffer.contentsAsString();
+            return _textBuffer.getContentsAsString();
         }
         return _getText2(_currToken);
     }
@@ -300,7 +300,7 @@ public class UTF8StreamJsonParser
                 _tokenIncomplete = false;
                 return _finishAndReturnString(); // only strings can be incomplete
             }
-            return _textBuffer.contentsAsString();
+            return _textBuffer.getContentsAsString();
         }
         return super.getValueAsString(null);
     }
@@ -314,7 +314,7 @@ public class UTF8StreamJsonParser
                 _tokenIncomplete = false;
                 return _finishAndReturnString(); // only strings can be incomplete
             }
-            return _textBuffer.contentsAsString();
+            return _textBuffer.getContentsAsString();
         }
         return super.getValueAsString(defValue);
     }
@@ -332,7 +332,7 @@ public class UTF8StreamJsonParser
             // fall through
         case ID_NUMBER_INT:
         case ID_NUMBER_FLOAT:
-            return _textBuffer.contentsAsString();
+            return _textBuffer.getContentsAsString();
         default:
         	return t.asString();
         }
@@ -391,7 +391,7 @@ public class UTF8StreamJsonParser
                 // fall through
             case ID_NUMBER_INT:
             case ID_NUMBER_FLOAT:
-                return _textBuffer.size();
+                return _textBuffer.length();
                 
             default:
                 return _currToken.asCharArray().length;
@@ -1183,7 +1183,7 @@ public class UTF8StreamJsonParser
                     _tokenIncomplete = false;
                     return _finishAndReturnString();
                 }
-                return _textBuffer.contentsAsString();
+                return _textBuffer.getContentsAsString();
             }
             if (t == JsonToken.START_ARRAY) {
                 _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
@@ -1298,7 +1298,7 @@ public class UTF8StreamJsonParser
      */
     protected JsonToken _parsePosNumber(int c) throws IOException
     {
-        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
+        char[] outBuf = _textBuffer.clearAndGetCurrentSegment();
         // One special case: if first char is 0, must not be followed by a digit
         if (c == INT_0) {
             c = _verifyNoLeadingZeroes();
@@ -1340,7 +1340,7 @@ public class UTF8StreamJsonParser
     
     protected JsonToken _parseNegNumber() throws IOException
     {
-        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
+        char[] outBuf = _textBuffer.clearAndGetCurrentSegment();
         int outPtr = 0;
 
         // Need to prepend sign?
@@ -1420,7 +1420,7 @@ public class UTF8StreamJsonParser
                 break;
             }
             if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
+                outBuf = _textBuffer.completeCurrentSegment();
                 outPtr = 0;
             }
             outBuf[outPtr++] = (char) c;
@@ -1496,7 +1496,7 @@ public class UTF8StreamJsonParser
                 }
                 ++fractLen;
                 if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
+                    outBuf = _textBuffer.completeCurrentSegment();
                     outPtr = 0;
                 }
                 outBuf[outPtr++] = (char) c;
@@ -1510,7 +1510,7 @@ public class UTF8StreamJsonParser
         int expLen = 0;
         if (c == INT_e || c == INT_E) { // exponent?
             if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
+                outBuf = _textBuffer.completeCurrentSegment();
                 outPtr = 0;
             }
             outBuf[outPtr++] = (char) c;
@@ -1522,7 +1522,7 @@ public class UTF8StreamJsonParser
             // Sign indicator?
             if (c == '-' || c == '+') {
                 if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
+                    outBuf = _textBuffer.completeCurrentSegment();
                     outPtr = 0;
                 }
                 outBuf[outPtr++] = (char) c;
@@ -1537,7 +1537,7 @@ public class UTF8StreamJsonParser
             while (c <= INT_9 && c >= INT_0) {
                 ++expLen;
                 if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
+                    outBuf = _textBuffer.completeCurrentSegment();
                     outPtr = 0;
                 }
                 outBuf[outPtr++] = (char) c;
@@ -2216,7 +2216,7 @@ public class UTF8StreamJsonParser
         }
 
         // Need some working space, TextBuffer works well:
-        char[] cbuf = _textBuffer.emptyAndGetCurrentSegment();
+        char[] cbuf = _textBuffer.clearAndGetCurrentSegment();
         int cix = 0;
 
         for (int ix = 0; ix < byteLen; ) {
@@ -2278,14 +2278,14 @@ public class UTF8StreamJsonParser
                 if (needed > 2) { // surrogate pair? once again, let's output one here, one later on
                     ch -= 0x10000; // to normalize it starting with 0x0
                     if (cix >= cbuf.length) {
-                        cbuf = _textBuffer.expandCurrentSegment();
+                        cbuf = _textBuffer.growCurrentSegment();
                     }
                     cbuf[cix++] = (char) (0xD800 + (ch >> 10));
                     ch = 0xDC00 | (ch & 0x03FF);
                 }
             }
             if (cix >= cbuf.length) {
-                cbuf = _textBuffer.expandCurrentSegment();
+                cbuf = _textBuffer.growCurrentSegment();
             }
             cbuf[cix++] = (char) ch;
         }
@@ -2315,7 +2315,7 @@ public class UTF8StreamJsonParser
             ptr = _inputPtr;
         }
         int outPtr = 0;
-        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
+        char[] outBuf = _textBuffer.clearAndGetCurrentSegment();
         final int[] codes = _icUTF8;
 
         final int max = Math.min(_inputEnd, (ptr + outBuf.length));
@@ -2349,7 +2349,7 @@ public class UTF8StreamJsonParser
             ptr = _inputPtr;
         }
         int outPtr = 0;
-        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
+        char[] outBuf = _textBuffer.clearAndGetCurrentSegment();
         final int[] codes = _icUTF8;
 
         final int max = Math.min(_inputEnd, (ptr + outBuf.length));
@@ -2368,7 +2368,7 @@ public class UTF8StreamJsonParser
         }
         _inputPtr = ptr;
         _finishString2(outBuf, outPtr);
-        return _textBuffer.contentsAsString();
+        return _textBuffer.getContentsAsString();
     }
     
     private final void _finishString2(char[] outBuf, int outPtr)
@@ -2391,7 +2391,7 @@ public class UTF8StreamJsonParser
                     ptr = _inputPtr;
                 }
                 if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
+                    outBuf = _textBuffer.completeCurrentSegment();
                     outPtr = 0;
                 }
                 final int max = Math.min(_inputEnd, (ptr + (outBuf.length - outPtr)));
@@ -2429,7 +2429,7 @@ public class UTF8StreamJsonParser
                 // Let's add first part right away:
                 outBuf[outPtr++] = (char) (0xD800 | (c >> 10));
                 if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
+                    outBuf = _textBuffer.completeCurrentSegment();
                     outPtr = 0;
                 }
                 c = 0xDC00 | (c & 0x3FF);
@@ -2446,7 +2446,7 @@ public class UTF8StreamJsonParser
             }
             // Need more room?
             if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
+                outBuf = _textBuffer.completeCurrentSegment();
                 outPtr = 0;
             }
             // Ok, let's add char to output:
@@ -2576,7 +2576,7 @@ public class UTF8StreamJsonParser
         int c = 0;
         // Otherwise almost verbatim copy of _finishString()
         int outPtr = 0;
-        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
+        char[] outBuf = _textBuffer.clearAndGetCurrentSegment();
 
         // Here we do want to do full decoding, hence:
         final int[] codes = _icUTF8;
@@ -2591,7 +2591,7 @@ public class UTF8StreamJsonParser
                     loadMoreGuaranteed();
                 }
                 if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
+                    outBuf = _textBuffer.completeCurrentSegment();
                     outPtr = 0;
                 }
                 int max = _inputEnd;
@@ -2636,7 +2636,7 @@ public class UTF8StreamJsonParser
                 // Let's add first part right away:
                 outBuf[outPtr++] = (char) (0xD800 | (c >> 10));
                 if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
+                    outBuf = _textBuffer.completeCurrentSegment();
                     outPtr = 0;
                 }
                 c = 0xDC00 | (c & 0x3FF);
@@ -2651,7 +2651,7 @@ public class UTF8StreamJsonParser
             }
             // Need more room?
             if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
+                outBuf = _textBuffer.completeCurrentSegment();
                 outPtr = 0;
             }
             // Ok, let's add char to output:
diff --git a/src/main/java/com/fasterxml/jackson/core/util/SegmentedTextBuffer.java b/src/main/java/com/fasterxml/jackson/core/util/SegmentedTextBuffer.java
new file mode 100644
index 00000000..e14f6efb
--- /dev/null
+++ b/src/main/java/com/fasterxml/jackson/core/util/SegmentedTextBuffer.java
@@ -0,0 +1,733 @@
+package com.fasterxml.jackson.core.util;
+
+import java.math.BigDecimal;
+import java.util.ArrayList;
+import java.util.Arrays;
+
+import com.fasterxml.jackson.core.io.NumberInput;
+
+/**
+ * TextBuffer is a class similar to {@link StringBuffer}, with
+ * following differences:
+ *<ul>
+ *  <li>TextBuffer uses segments character arrays, to avoid having
+ *     to do additional array copies when array is not big enough.
+ *     This means that only reallocating that is necessary is done only once:
+ *     if and when caller
+ *     wants to access contents in a linear array (char[], String).
+ *    </li>
+*  <li>TextBuffer can also be initialized in "shared mode", in which
+*     it will just act as a wrapper to a single char array managed
+*     by another object (like parser that owns it)
+ *    </li>
+ *  <li>TextBuffer is not synchronized.
+ *    </li>
+ * </ul>
+ */
+public final class SegmentedTextBuffer
+{
+    final static char[] EMPTY_CHARS = new char[0];
+
+    /**
+     * Let's start with sizable but not huge buffer, will grow as necessary
+     */
+    final static int MIN_SEGMENT_LENGTH = 1000;
+    
+    /**
+     * Let's limit maximum segment length to something sensible
+     * like 256k
+     */
+    final static int MAX_SEGMENT_LENGTH = 0x40000;
+    
+    /*
+    /**********************************************************
+    /* Configuration:
+    /**********************************************************
+     */
+
+    private final BufferRecycler bufferRecycler;
+
+    /*
+    /**********************************************************
+    /* Shared input buffers
+    /**********************************************************
+     */
+
+    /**
+     * Shared input buffer; stored here in case some input can be returned
+     * as is, without being copied to collector's own buffers. Note that
+     * this is read-only for this Object.
+     */
+    private char[] inputBuf;
+
+    /**
+     * Character offset of first char in input buffer; -1 to indicate
+     * that input buffer currently does not contain any useful char data
+     */
+    private int inputOffset;
+
+    private int inputLength;
+
+    /*
+    /**********************************************************
+    /* Aggregation segments (when not using input buf)
+    /**********************************************************
+     */
+
+    /**
+     * List of segments prior to currently active segment.
+     */
+    private ArrayList<char[]> segmentsList;
+
+    /**
+     * Flag that indicates whether _seqments is non-empty
+     */
+    private boolean segmentsPresent = false;
+
+    // // // Currently used segment; not (yet) contained in _seqments
+
+    /**
+     * Amount of characters in segments in {@link segmentsList}
+     */
+    private int segmentCapacity;
+
+    private char[] activeSegment;
+
+    /**
+     * Number of characters in currently active (last) segment
+     */
+    private int currentLength;
+
+    /*
+    /**********************************************************
+    /* Caching of results
+    /**********************************************************
+     */
+
+    /**
+     * String that will be constructed when the whole contents are
+     * needed; will be temporarily stored in case asked for again.
+     */
+    private String cachedResultString;
+
+    private char[] resultCharArray;
+
+    /*
+    /**********************************************************
+    /* Life-cycle
+    /**********************************************************
+     */
+
+    public SegmentedTextBuffer(BufferRecycler bufferRecyclerParam) {
+        bufferRecycler = bufferRecyclerParam;
+    }
+
+    /**
+     * Method called to indicate that the underlying buffers should now
+     * be recycled if they haven't yet been recycled. Although caller
+     * can still use this text buffer, it is not advisable to call this
+     * method if that is likely, since next time a buffer is needed,
+     * buffers need to reallocated.
+     * Note: calling this method automatically also clears contents
+     * of the buffer.
+     */
+    public void releaseCharBuffers()
+    {
+        if (bufferRecycler == null) {
+            resetToEmpty();
+        } else {
+            if (activeSegment != null) {
+                // First, let's get rid of all but the largest char array
+                resetToEmpty();
+                // And then return that array
+                char[] charBuf = activeSegment;
+                activeSegment = null;
+                bufferRecycler.releaseCharBuffer(BufferRecycler.CHAR_TEXT_BUFFER, charBuf);
+            }
+        }
+    }
+
+    /**
+     * Method called to clear out any content text buffer may have, and
+     * initializes buffer to use non-shared data.
+     */
+    public void resetToEmpty()
+    {
+        inputOffset = -1; // indicates shared buffer not used
+        currentLength = 0;
+        inputLength = 0;
+
+        inputBuf = null;
+        cachedResultString = null;
+        resultCharArray = null;
+
+        // And then reset internal input buffers, if necessary:
+        if (segmentsPresent) {
+            clearAllSegments();
+        }
+    }
+
+    /**
+     * Method called to initialize the buffer with a shared copy of data;
+     * this means that buffer will just have pointers to actual data. It
+     * also means that if anything is to be appended to the buffer, it
+     * will first have to unshare it (make a local copy).
+     */
+    public void resetWithSharedBuffer(char[] charBuf, int startIndex, int length)
+    {
+        // First, let's clear intermediate values, if any:
+        cachedResultString = null;
+        resultCharArray = null;
+
+        // Then let's mark things we need about input buffer
+        inputBuf = charBuf;
+        inputOffset = startIndex;
+        inputLength = length;
+
+        // And then reset internal input buffers, if necessary:
+        if (segmentsPresent) {
+            clearAllSegments();
+        }
+    }
+
+    public void resetAndCopy(char[] charBuf, int startIndex, int length)
+    {
+        inputBuf = null;
+        inputOffset = -1; // indicates shared buffer not used
+        inputLength = 0;
+
+        cachedResultString = null;
+        resultCharArray = null;
+
+        // And then reset internal input buffers, if necessary:
+        if (segmentsPresent) {
+            clearAllSegments();
+        } else if (activeSegment == null) {
+            activeSegment = charBuf(length);
+        }
+        currentLength = segmentCapacity = 0;
+        appendChar(charBuf, startIndex, length);
+    }
+
+    public void resetToString(String strValue)
+    {
+        inputBuf = null;
+        inputOffset = -1;
+        inputLength = 0;
+
+        cachedResultString = strValue;
+        resultCharArray = null;
+
+        if (segmentsPresent) {
+            clearAllSegments();
+        }
+        currentLength = 0;
+        
+    }
+    
+    /**
+     * Helper method used to find a buffer to use, ideally one
+     * recycled earlier.
+     */
+    private char[] charBuf(int neededAmount)
+    {
+        if (bufferRecycler != null) {
+            return bufferRecycler.allocCharBuffer(BufferRecycler.CHAR_TEXT_BUFFER, neededAmount);
+        }
+        return new char[Math.max(neededAmount, MIN_SEGMENT_LENGTH)];
+    }
+
+    private void clearAllSegments()
+    {
+        segmentsPresent = false;
+        /* Let's start using _last_ segment from list; for one, it's
+         * the biggest one, and it's also most likely to be cached
+         */
+        /* 28-Aug-2009, tatu: Actually, the current segment should
+         *   be the biggest one, already
+         */
+        //_currentSegment = _segments.get(_segments.size() - 1);
+        segmentsList.clear();
+        currentLength = segmentCapacity = 0;
+    }
+
+    /*
+    /**********************************************************
+    /* Accessors for implementing public interface
+    /**********************************************************
+     */
+
+    /**
+     * @return Number of characters currently stored by this collector
+     */
+    public int length() {
+        if (inputOffset >= 0) { // shared copy from input buf
+            return inputLength;
+        }
+        if (resultCharArray != null) {
+            return resultCharArray.length;
+        }
+        if (cachedResultString != null) {
+            return cachedResultString.length();
+        }
+        // local segmented buffers
+        return segmentCapacity + currentLength;
+    }
+
+    public int getTextOffset() {
+        /* Only shared input buffer can have non-zero offset; buffer
+         * segments start at 0, and if we have to create a combo buffer,
+         * that too will start from beginning of the buffer
+         */
+        return (inputOffset >= 0) ? inputOffset : 0;
+    }
+
+    /**
+     * Method that can be used to check whether textual contents can
+     * be efficiently accessed using {@link #getTextBuffer}.
+     */
+    public boolean isTextStoredAsCharArray()
+    {
+        // if we have array in some form, sure
+        if (inputOffset >= 0 || resultCharArray != null)  return true;
+        // not if we have String as value
+        if (cachedResultString != null) return false;
+        return true;
+    }
+    
+    public char[] getTextBuffer()
+    {
+        // Are we just using shared input buffer?
+        if (inputOffset >= 0) return inputBuf;
+        if (resultCharArray != null)  return resultCharArray;
+        if (cachedResultString != null) {
+            return (resultCharArray = cachedResultString.toCharArray());
+        }
+        // Nope; but does it fit in just one segment?
+        if (!segmentsPresent)  return activeSegment;
+        // Nope, need to have/create a non-segmented array and return it
+        return contentsAsCharArray();
+    }
+
+    /*
+    /**********************************************************
+    /* Other accessors:
+    /**********************************************************
+     */
+
+    public String getContentsAsString()
+    {
+        if (cachedResultString == null) {
+            // Has array been requested? Can make a shortcut, if so:
+            if (resultCharArray != null) {
+                cachedResultString = new String(resultCharArray);
+            } else {
+                // Do we use shared array?
+                if (inputOffset >= 0) {
+                    if (inputLength < 1) {
+                        return (cachedResultString = "");
+                    }
+                    cachedResultString = new String(inputBuf, inputOffset, inputLength);
+                } else { // nope... need to copy
+                    // But first, let's see if we have just one buffer
+                    int segmentLength = segmentCapacity;
+                    int currentLength = this.currentLength;
+                    
+                    if (segmentLength == 0) { // yup
+                        cachedResultString = (currentLength == 0) ? "" : new String(activeSegment, 0, currentLength);
+                    } else { // no, need to combine
+                        StringBuilder sbuilder = new StringBuilder(segmentLength + currentLength);
+                        // First stored segments
+                        if (segmentsList != null) {
+                            for (int idx = 0, length = segmentsList.size(); idx < length; ++idx) {
+                                char[] currSeg = segmentsList.get(idx);
+                                sbuilder.append(currSeg, 0, currSeg.length);
+                            }
+                        }
+                        // And finally, current segment:
+                        sbuilder.append(activeSegment, 0, this.currentLength);
+                        cachedResultString = sbuilder.toString();
+                    }
+                }
+            }
+        }
+        return cachedResultString;
+    }
+ 
+    public char[] contentsAsCharArray() {
+        char[] outArray = resultCharArray;
+        if (outArray == null) {
+            resultCharArray = outArray = toCharArray();
+        }
+        return outArray;
+    }
+
+    /**
+     * Convenience method for converting contents of the buffer
+     * into a {@link BigDecimal}.
+     */
+    public BigDecimal contentsAsBigDecimal() throws NumberFormatException
+    {
+        // Already got a pre-cut array?
+        if (resultCharArray != null) {
+            return NumberInput.parseBigDecimal(resultCharArray);
+        }
+        // Or a shared buffer?
+        if ((inputOffset >= 0) && (inputBuf != null)) {
+            return NumberInput.parseBigDecimal(inputBuf, inputOffset, inputLength);
+        }
+        // Or if not, just a single buffer (the usual case)
+        if ((segmentCapacity == 0) && (activeSegment != null)) {
+            return NumberInput.parseBigDecimal(activeSegment, 0, currentLength);
+        }
+        // If not, let's just get it aggregated...
+        return NumberInput.parseBigDecimal(contentsAsCharArray());
+    }
+
+    /**
+     * Convenience method for converting contents of the buffer
+     * into a Double value.
+     */
+    public double getContentsAsDouble() throws NumberFormatException {
+        return NumberInput.parseDouble(getContentsAsString());
+    }
+
+    /*
+    /**********************************************************
+    /* Public mutators:
+    /**********************************************************
+     */
+
+    /**
+     * Method called to make sure that buffer is not using shared input
+     * buffer; if it is, it will copy such contents to private buffer.
+     */
+    public void ensureUnshared() {
+        if (inputOffset >= 0) {
+            ensureUnshared(16);
+        }
+    }
+
+    public void appendChar(char ch) {
+        // Using shared buffer so far?
+        if (inputOffset >= 0) {
+            ensureUnshared(16);
+        }
+        cachedResultString = null;
+        resultCharArray = null;
+        // Room in current segment?
+        char[] currSeg = activeSegment;
+        if (currentLength >= currSeg.length) {
+            expandSegment(1);
+            currSeg = activeSegment;
+        }
+        currSeg[currentLength++] = ch;
+    }
+
+    public void appendChar(char[] ch, int startIndex, int length)
+    {
+        // Can't append to shared buf (sanity check)
+        if (inputOffset >= 0) {
+            ensureUnshared(length);
+        }
+        cachedResultString = null;
+        resultCharArray = null;
+
+        // Room in current segment?
+        char[] currSeg = activeSegment;
+        int maxCopy = currSeg.length - currentLength;
+            
+        if (maxCopy >= length) {
+            System.arraycopy(ch, startIndex, currSeg, currentLength, length);
+            currentLength += length;
+            return;
+        }
+        // No room for all, need to copy part(s):
+        if (maxCopy > 0) {
+            System.arraycopy(ch, startIndex, currSeg, currentLength, maxCopy);
+            startIndex += maxCopy;
+            length -= maxCopy;
+        }
+        /* And then allocate new segment; we are guaranteed to now
+         * have enough room in segment.
+         */
+        // Except, as per [Issue-24], not for HUGE appends... so:
+        do {
+            expandSegment(length);
+            int toCopy = Math.min(activeSegment.length, length);
+            System.arraycopy(ch, startIndex, activeSegment, 0, toCopy);
+            currentLength += toCopy;
+            startIndex += toCopy;
+            length -= toCopy;
+        } while (length > 0);
+    }
+
+    public void appendChar(String sourceString, int srcOffset, int length)
+    {
+        // Can't append to shared buf (sanity check)
+        if (inputOffset >= 0) {
+            ensureUnshared(length);
+        }
+        cachedResultString = null;
+        resultCharArray = null;
+
+        // Room in current segment?
+        char[] currSeg = activeSegment;
+        int maxCopy = currSeg.length - currentLength;
+        if (maxCopy >= length) {
+            sourceString.getChars(srcOffset, srcOffset + length, currSeg, currentLength);
+            currentLength += length;
+            return;
+        }
+        // No room for all, need to copy part(s):
+        if (maxCopy > 0) {
+            sourceString.getChars(srcOffset, srcOffset + maxCopy, currSeg, currentLength);
+            length -= maxCopy;
+            srcOffset += maxCopy;
+        }
+        /* And then allocate new segment; we are guaranteed to now
+         * have enough room in segment.
+         */
+        // Except, as per [Issue-24], not for HUGE appends... so:
+        do {
+            expandSegment(length);
+            int toCopy = Math.min(activeSegment.length, length);
+            sourceString.getChars(srcOffset, srcOffset + toCopy, activeSegment, 0);
+            currentLength += toCopy;
+            srcOffset += toCopy;
+            length -= toCopy;
+        } while (length > 0);
+    }
+
+    /*
+    /**********************************************************
+    /* Raw access, for high-performance use:
+    /**********************************************************
+     */
+
+    public char[] getCurrentSegment()
+    {
+        /* Since the intention of the caller is to directly add stuff into
+         * buffers, we should NOT have anything in shared buffer... ie. may
+         * need to unshare contents.
+         */
+        if (inputOffset >= 0) {
+            ensureUnshared(1);
+        } else {
+            char[] currSeg = activeSegment;
+            if (currSeg == null) {
+                activeSegment = charBuf(0);
+            } else if (currentLength >= currSeg.length) {
+                // Plus, we better have room for at least one more char
+                expandSegment(1);
+            }
+        }
+        return activeSegment;
+    }
+
+    public char[] clearAndGetCurrentSegment()
+    {
+        // inlined 'resetWithEmpty()'
+        inputOffset = -1; // indicates shared buffer not used
+        currentLength = 0;
+        inputLength = 0;
+
+        inputBuf = null;
+        cachedResultString = null;
+        resultCharArray = null;
+
+        // And then reset internal input buffers, if necessary:
+        if (segmentsPresent) {
+            clearAllSegments();
+        }
+        char[] currSeg = activeSegment;
+        if (currSeg == null) {
+            activeSegment = currSeg = charBuf(0);
+        }
+        return currSeg;
+    }
+
+    public int getCurrentSegmentSize() { return currentLength; }
+    public void setCurrentLength(int length) { currentLength = length; }
+
+    /**
+     * @since 2.6
+     */
+    public String setCurrentAndReturn(int length) {
+        currentLength = length;
+        // We can simplify handling here compared to full `contentsAsString()`:
+        if (segmentCapacity > 0) { // longer text; call main method
+            return getContentsAsString();
+        }
+        // more common case: single segment
+        int currentLength = this.currentLength;
+        String sourceString = (currentLength == 0) ? "" : new String(activeSegment, 0, currentLength);
+        cachedResultString = sourceString;
+        return sourceString;
+    }
+    
+    public char[] completeCurrentSegment() {
+        if (segmentsList == null) {
+            segmentsList = new ArrayList<char[]>();
+        }
+        segmentsPresent = true;
+        segmentsList.add(activeSegment);
+        int previousLength = activeSegment.length;
+        segmentCapacity += previousLength;
+        currentLength = 0;
+
+        // Let's grow segments by 50%
+        int newLength = previousLength + (previousLength >> 1);
+        if (newLength < MIN_SEGMENT_LENGTH) {
+            newLength = MIN_SEGMENT_LENGTH;
+        } else if (newLength > MAX_SEGMENT_LENGTH) {
+            newLength = MAX_SEGMENT_LENGTH;
+        }
+        char[] currSeg = charArray(newLength);
+        activeSegment = currSeg;
+        return currSeg;
+    }
+
+    /**
+     * Method called to expand size of the current segment, to
+     * accommodate for more contiguous content. Usually only
+     * used when parsing tokens like names if even then.
+     */
+    public char[] growCurrentSegment()
+    {
+        final char[] currSeg = activeSegment;
+        // Let's grow by 50% by default
+        final int length = currSeg.length;
+        int newLength = length + (length >> 1);
+        // but above intended maximum, slow to increase by 25%
+        if (newLength > MAX_SEGMENT_LENGTH) {
+            newLength = length + (length >> 2);
+        }
+        return (activeSegment = Arrays.copyOf(currSeg, newLength));
+    }
+
+    /**
+     * Method called to expand size of the current segment, to
+     * accommodate for more contiguous content. Usually only
+     * used when parsing tokens like names if even then.
+     * 
+     * @param minRequired Required minimum strength of the current segment
+     *
+     * @since 2.4.0
+     */
+    public char[] growCurrentSegment(int minRequired) {
+        char[] currSeg = activeSegment;
+        if (currSeg.length >= minRequired) return currSeg;
+        activeSegment = currSeg = Arrays.copyOf(currSeg, minRequired);
+        return currSeg;
+    }
+
+    /*
+    /**********************************************************
+    /* Standard methods:
+    /**********************************************************
+     */
+
+    /**
+     * Note: calling this method may not be as efficient as calling
+     * {@link #getContentsAsString}, since it's not guaranteed that resulting
+     * String is cached.
+     */
+    @Override public String toString() { return getContentsAsString(); }
+
+    /*
+    /**********************************************************
+    /* Internal methods:
+    /**********************************************************
+     */
+
+    /**
+     * Method called if/when we need to append content when we have been
+     * initialized to use shared buffer.
+     */
+    private void ensureUnshared(int extraNeeded)
+    {
+        int sharedLength = inputLength;
+        inputLength = 0;
+        char[] sharedBuf = inputBuf;
+        inputBuf = null;
+        int startIndex = inputOffset;
+        inputOffset = -1;
+
+        // Is buffer big enough, or do we need to reallocate?
+        int neededAmount = sharedLength + extraNeeded;
+        if (activeSegment == null || neededAmount > activeSegment.length) {
+            activeSegment = charBuf(neededAmount);
+        }
+        if (sharedLength > 0) {
+            System.arraycopy(sharedBuf, startIndex, activeSegment, 0, sharedLength);
+        }
+        segmentCapacity = 0;
+        currentLength = sharedLength;
+    }
+
+    /**
+     * Method called when current segment is full, to allocate new
+     * segment.
+     */
+    private void expandSegment(int minNewSize)
+    {
+        // First, let's move current segment to segment list:
+        if (segmentsList == null) {
+            segmentsList = new ArrayList<char[]>();
+        }
+        char[] currSeg = activeSegment;
+        segmentsPresent = true;
+        segmentsList.add(currSeg);
+        segmentCapacity += currSeg.length;
+        currentLength = 0;
+        int previousLength = currSeg.length;
+        
+        // Let's grow segments by 50% minimum
+        int newLength = previousLength + (previousLength >> 1);
+        if (newLength < MIN_SEGMENT_LENGTH) {
+            newLength = MIN_SEGMENT_LENGTH;
+        } else if (newLength > MAX_SEGMENT_LENGTH) {
+            newLength = MAX_SEGMENT_LENGTH;
+        }
+        activeSegment = charArray(newLength);
+    }
+
+    private char[] toCharArray()
+    {
+        if (cachedResultString != null) { // Can take a shortcut...
+            return cachedResultString.toCharArray();
+        }
+        // Do we use shared array?
+        if (inputOffset >= 0) {
+            final int length = inputLength;
+            if (length < 1) {
+                return EMPTY_CHARS;
+            }
+            final int startIndex = inputOffset;
+            if (startIndex == 0) {
+                return Arrays.copyOf(inputBuf, length);
+            }
+            return Arrays.copyOfRange(inputBuf, startIndex, startIndex + length);
+        }
+        // nope, not shared
+        int totalSize = length();
+        if (totalSize < 1) {
+            return EMPTY_CHARS;
+        }
+        int srcOffset = 0;
+        final char[] outArray = charArray(totalSize);
+        if (segmentsList != null) {
+            for (int idx = 0, length = segmentsList.size(); idx < length; ++idx) {
+                char[] currSeg = segmentsList.get(idx);
+                int currentLength = currSeg.length;
+                System.arraycopy(currSeg, 0, outArray, srcOffset, currentLength);
+                srcOffset += currentLength;
+            }
+        }
+        System.arraycopy(activeSegment, 0, outArray, srcOffset, currentLength);
+        return outArray;
+    }
+
+    private char[] charArray(int length) { return new char[length]; }
+}
diff --git a/src/main/java/com/fasterxml/jackson/core/util/TextBuffer.java b/src/main/java/com/fasterxml/jackson/core/util/TextBuffer.java
deleted file mode 100644
index e6f1cbc5..00000000
--- a/src/main/java/com/fasterxml/jackson/core/util/TextBuffer.java
+++ /dev/null
@@ -1,733 +0,0 @@
-package com.fasterxml.jackson.core.util;
-
-import java.math.BigDecimal;
-import java.util.ArrayList;
-import java.util.Arrays;
-
-import com.fasterxml.jackson.core.io.NumberInput;
-
-/**
- * TextBuffer is a class similar to {@link StringBuffer}, with
- * following differences:
- *<ul>
- *  <li>TextBuffer uses segments character arrays, to avoid having
- *     to do additional array copies when array is not big enough.
- *     This means that only reallocating that is necessary is done only once:
- *     if and when caller
- *     wants to access contents in a linear array (char[], String).
- *    </li>
-*  <li>TextBuffer can also be initialized in "shared mode", in which
-*     it will just act as a wrapper to a single char array managed
-*     by another object (like parser that owns it)
- *    </li>
- *  <li>TextBuffer is not synchronized.
- *    </li>
- * </ul>
- */
-public final class TextBuffer
-{
-    final static char[] NO_CHARS = new char[0];
-
-    /**
-     * Let's start with sizable but not huge buffer, will grow as necessary
-     */
-    final static int MIN_SEGMENT_LEN = 1000;
-    
-    /**
-     * Let's limit maximum segment length to something sensible
-     * like 256k
-     */
-    final static int MAX_SEGMENT_LEN = 0x40000;
-    
-    /*
-    /**********************************************************
-    /* Configuration:
-    /**********************************************************
-     */
-
-    private final BufferRecycler _allocator;
-
-    /*
-    /**********************************************************
-    /* Shared input buffers
-    /**********************************************************
-     */
-
-    /**
-     * Shared input buffer; stored here in case some input can be returned
-     * as is, without being copied to collector's own buffers. Note that
-     * this is read-only for this Object.
-     */
-    private char[] _inputBuffer;
-
-    /**
-     * Character offset of first char in input buffer; -1 to indicate
-     * that input buffer currently does not contain any useful char data
-     */
-    private int _inputStart;
-
-    private int _inputLen;
-
-    /*
-    /**********************************************************
-    /* Aggregation segments (when not using input buf)
-    /**********************************************************
-     */
-
-    /**
-     * List of segments prior to currently active segment.
-     */
-    private ArrayList<char[]> _segments;
-
-    /**
-     * Flag that indicates whether _seqments is non-empty
-     */
-    private boolean _hasSegments = false;
-
-    // // // Currently used segment; not (yet) contained in _seqments
-
-    /**
-     * Amount of characters in segments in {@link _segments}
-     */
-    private int _segmentSize;
-
-    private char[] _currentSegment;
-
-    /**
-     * Number of characters in currently active (last) segment
-     */
-    private int _currentSize;
-
-    /*
-    /**********************************************************
-    /* Caching of results
-    /**********************************************************
-     */
-
-    /**
-     * String that will be constructed when the whole contents are
-     * needed; will be temporarily stored in case asked for again.
-     */
-    private String _resultString;
-
-    private char[] _resultArray;
-
-    /*
-    /**********************************************************
-    /* Life-cycle
-    /**********************************************************
-     */
-
-    public TextBuffer(BufferRecycler allocator) {
-        _allocator = allocator;
-    }
-
-    /**
-     * Method called to indicate that the underlying buffers should now
-     * be recycled if they haven't yet been recycled. Although caller
-     * can still use this text buffer, it is not advisable to call this
-     * method if that is likely, since next time a buffer is needed,
-     * buffers need to reallocated.
-     * Note: calling this method automatically also clears contents
-     * of the buffer.
-     */
-    public void releaseBuffers()
-    {
-        if (_allocator == null) {
-            resetWithEmpty();
-        } else {
-            if (_currentSegment != null) {
-                // First, let's get rid of all but the largest char array
-                resetWithEmpty();
-                // And then return that array
-                char[] buf = _currentSegment;
-                _currentSegment = null;
-                _allocator.releaseCharBuffer(BufferRecycler.CHAR_TEXT_BUFFER, buf);
-            }
-        }
-    }
-
-    /**
-     * Method called to clear out any content text buffer may have, and
-     * initializes buffer to use non-shared data.
-     */
-    public void resetWithEmpty()
-    {
-        _inputStart = -1; // indicates shared buffer not used
-        _currentSize = 0;
-        _inputLen = 0;
-
-        _inputBuffer = null;
-        _resultString = null;
-        _resultArray = null;
-
-        // And then reset internal input buffers, if necessary:
-        if (_hasSegments) {
-            clearSegments();
-        }
-    }
-
-    /**
-     * Method called to initialize the buffer with a shared copy of data;
-     * this means that buffer will just have pointers to actual data. It
-     * also means that if anything is to be appended to the buffer, it
-     * will first have to unshare it (make a local copy).
-     */
-    public void resetWithShared(char[] buf, int start, int len)
-    {
-        // First, let's clear intermediate values, if any:
-        _resultString = null;
-        _resultArray = null;
-
-        // Then let's mark things we need about input buffer
-        _inputBuffer = buf;
-        _inputStart = start;
-        _inputLen = len;
-
-        // And then reset internal input buffers, if necessary:
-        if (_hasSegments) {
-            clearSegments();
-        }
-    }
-
-    public void resetWithCopy(char[] buf, int start, int len)
-    {
-        _inputBuffer = null;
-        _inputStart = -1; // indicates shared buffer not used
-        _inputLen = 0;
-
-        _resultString = null;
-        _resultArray = null;
-
-        // And then reset internal input buffers, if necessary:
-        if (_hasSegments) {
-            clearSegments();
-        } else if (_currentSegment == null) {
-            _currentSegment = buf(len);
-        }
-        _currentSize = _segmentSize = 0;
-        append(buf, start, len);
-    }
-
-    public void resetWithString(String value)
-    {
-        _inputBuffer = null;
-        _inputStart = -1;
-        _inputLen = 0;
-
-        _resultString = value;
-        _resultArray = null;
-
-        if (_hasSegments) {
-            clearSegments();
-        }
-        _currentSize = 0;
-        
-    }
-    
-    /**
-     * Helper method used to find a buffer to use, ideally one
-     * recycled earlier.
-     */
-    private char[] buf(int needed)
-    {
-        if (_allocator != null) {
-            return _allocator.allocCharBuffer(BufferRecycler.CHAR_TEXT_BUFFER, needed);
-        }
-        return new char[Math.max(needed, MIN_SEGMENT_LEN)];
-    }
-
-    private void clearSegments()
-    {
-        _hasSegments = false;
-        /* Let's start using _last_ segment from list; for one, it's
-         * the biggest one, and it's also most likely to be cached
-         */
-        /* 28-Aug-2009, tatu: Actually, the current segment should
-         *   be the biggest one, already
-         */
-        //_currentSegment = _segments.get(_segments.size() - 1);
-        _segments.clear();
-        _currentSize = _segmentSize = 0;
-    }
-
-    /*
-    /**********************************************************
-    /* Accessors for implementing public interface
-    /**********************************************************
-     */
-
-    /**
-     * @return Number of characters currently stored by this collector
-     */
-    public int size() {
-        if (_inputStart >= 0) { // shared copy from input buf
-            return _inputLen;
-        }
-        if (_resultArray != null) {
-            return _resultArray.length;
-        }
-        if (_resultString != null) {
-            return _resultString.length();
-        }
-        // local segmented buffers
-        return _segmentSize + _currentSize;
-    }
-
-    public int getTextOffset() {
-        /* Only shared input buffer can have non-zero offset; buffer
-         * segments start at 0, and if we have to create a combo buffer,
-         * that too will start from beginning of the buffer
-         */
-        return (_inputStart >= 0) ? _inputStart : 0;
-    }
-
-    /**
-     * Method that can be used to check whether textual contents can
-     * be efficiently accessed using {@link #getTextBuffer}.
-     */
-    public boolean hasTextAsCharacters()
-    {
-        // if we have array in some form, sure
-        if (_inputStart >= 0 || _resultArray != null)  return true;
-        // not if we have String as value
-        if (_resultString != null) return false;
-        return true;
-    }
-    
-    public char[] getTextBuffer()
-    {
-        // Are we just using shared input buffer?
-        if (_inputStart >= 0) return _inputBuffer;
-        if (_resultArray != null)  return _resultArray;
-        if (_resultString != null) {
-            return (_resultArray = _resultString.toCharArray());
-        }
-        // Nope; but does it fit in just one segment?
-        if (!_hasSegments)  return _currentSegment;
-        // Nope, need to have/create a non-segmented array and return it
-        return contentsAsArray();
-    }
-
-    /*
-    /**********************************************************
-    /* Other accessors:
-    /**********************************************************
-     */
-
-    public String contentsAsString()
-    {
-        if (_resultString == null) {
-            // Has array been requested? Can make a shortcut, if so:
-            if (_resultArray != null) {
-                _resultString = new String(_resultArray);
-            } else {
-                // Do we use shared array?
-                if (_inputStart >= 0) {
-                    if (_inputLen < 1) {
-                        return (_resultString = "");
-                    }
-                    _resultString = new String(_inputBuffer, _inputStart, _inputLen);
-                } else { // nope... need to copy
-                    // But first, let's see if we have just one buffer
-                    int segLen = _segmentSize;
-                    int currLen = _currentSize;
-                    
-                    if (segLen == 0) { // yup
-                        _resultString = (currLen == 0) ? "" : new String(_currentSegment, 0, currLen);
-                    } else { // no, need to combine
-                        StringBuilder sb = new StringBuilder(segLen + currLen);
-                        // First stored segments
-                        if (_segments != null) {
-                            for (int i = 0, len = _segments.size(); i < len; ++i) {
-                                char[] curr = _segments.get(i);
-                                sb.append(curr, 0, curr.length);
-                            }
-                        }
-                        // And finally, current segment:
-                        sb.append(_currentSegment, 0, _currentSize);
-                        _resultString = sb.toString();
-                    }
-                }
-            }
-        }
-        return _resultString;
-    }
- 
-    public char[] contentsAsArray() {
-        char[] result = _resultArray;
-        if (result == null) {
-            _resultArray = result = resultArray();
-        }
-        return result;
-    }
-
-    /**
-     * Convenience method for converting contents of the buffer
-     * into a {@link BigDecimal}.
-     */
-    public BigDecimal contentsAsDecimal() throws NumberFormatException
-    {
-        // Already got a pre-cut array?
-        if (_resultArray != null) {
-            return NumberInput.parseBigDecimal(_resultArray);
-        }
-        // Or a shared buffer?
-        if ((_inputStart >= 0) && (_inputBuffer != null)) {
-            return NumberInput.parseBigDecimal(_inputBuffer, _inputStart, _inputLen);
-        }
-        // Or if not, just a single buffer (the usual case)
-        if ((_segmentSize == 0) && (_currentSegment != null)) {
-            return NumberInput.parseBigDecimal(_currentSegment, 0, _currentSize);
-        }
-        // If not, let's just get it aggregated...
-        return NumberInput.parseBigDecimal(contentsAsArray());
-    }
-
-    /**
-     * Convenience method for converting contents of the buffer
-     * into a Double value.
-     */
-    public double contentsAsDouble() throws NumberFormatException {
-        return NumberInput.parseDouble(contentsAsString());
-    }
-
-    /*
-    /**********************************************************
-    /* Public mutators:
-    /**********************************************************
-     */
-
-    /**
-     * Method called to make sure that buffer is not using shared input
-     * buffer; if it is, it will copy such contents to private buffer.
-     */
-    public void ensureNotShared() {
-        if (_inputStart >= 0) {
-            unshare(16);
-        }
-    }
-
-    public void append(char c) {
-        // Using shared buffer so far?
-        if (_inputStart >= 0) {
-            unshare(16);
-        }
-        _resultString = null;
-        _resultArray = null;
-        // Room in current segment?
-        char[] curr = _currentSegment;
-        if (_currentSize >= curr.length) {
-            expand(1);
-            curr = _currentSegment;
-        }
-        curr[_currentSize++] = c;
-    }
-
-    public void append(char[] c, int start, int len)
-    {
-        // Can't append to shared buf (sanity check)
-        if (_inputStart >= 0) {
-            unshare(len);
-        }
-        _resultString = null;
-        _resultArray = null;
-
-        // Room in current segment?
-        char[] curr = _currentSegment;
-        int max = curr.length - _currentSize;
-            
-        if (max >= len) {
-            System.arraycopy(c, start, curr, _currentSize, len);
-            _currentSize += len;
-            return;
-        }
-        // No room for all, need to copy part(s):
-        if (max > 0) {
-            System.arraycopy(c, start, curr, _currentSize, max);
-            start += max;
-            len -= max;
-        }
-        /* And then allocate new segment; we are guaranteed to now
-         * have enough room in segment.
-         */
-        // Except, as per [Issue-24], not for HUGE appends... so:
-        do {
-            expand(len);
-            int amount = Math.min(_currentSegment.length, len);
-            System.arraycopy(c, start, _currentSegment, 0, amount);
-            _currentSize += amount;
-            start += amount;
-            len -= amount;
-        } while (len > 0);
-    }
-
-    public void append(String str, int offset, int len)
-    {
-        // Can't append to shared buf (sanity check)
-        if (_inputStart >= 0) {
-            unshare(len);
-        }
-        _resultString = null;
-        _resultArray = null;
-
-        // Room in current segment?
-        char[] curr = _currentSegment;
-        int max = curr.length - _currentSize;
-        if (max >= len) {
-            str.getChars(offset, offset+len, curr, _currentSize);
-            _currentSize += len;
-            return;
-        }
-        // No room for all, need to copy part(s):
-        if (max > 0) {
-            str.getChars(offset, offset+max, curr, _currentSize);
-            len -= max;
-            offset += max;
-        }
-        /* And then allocate new segment; we are guaranteed to now
-         * have enough room in segment.
-         */
-        // Except, as per [Issue-24], not for HUGE appends... so:
-        do {
-            expand(len);
-            int amount = Math.min(_currentSegment.length, len);
-            str.getChars(offset, offset+amount, _currentSegment, 0);
-            _currentSize += amount;
-            offset += amount;
-            len -= amount;
-        } while (len > 0);
-    }
-
-    /*
-    /**********************************************************
-    /* Raw access, for high-performance use:
-    /**********************************************************
-     */
-
-    public char[] getCurrentSegment()
-    {
-        /* Since the intention of the caller is to directly add stuff into
-         * buffers, we should NOT have anything in shared buffer... ie. may
-         * need to unshare contents.
-         */
-        if (_inputStart >= 0) {
-            unshare(1);
-        } else {
-            char[] curr = _currentSegment;
-            if (curr == null) {
-                _currentSegment = buf(0);
-            } else if (_currentSize >= curr.length) {
-                // Plus, we better have room for at least one more char
-                expand(1);
-            }
-        }
-        return _currentSegment;
-    }
-
-    public char[] emptyAndGetCurrentSegment()
-    {
-        // inlined 'resetWithEmpty()'
-        _inputStart = -1; // indicates shared buffer not used
-        _currentSize = 0;
-        _inputLen = 0;
-
-        _inputBuffer = null;
-        _resultString = null;
-        _resultArray = null;
-
-        // And then reset internal input buffers, if necessary:
-        if (_hasSegments) {
-            clearSegments();
-        }
-        char[] curr = _currentSegment;
-        if (curr == null) {
-            _currentSegment = curr = buf(0);
-        }
-        return curr;
-    }
-
-    public int getCurrentSegmentSize() { return _currentSize; }
-    public void setCurrentLength(int len) { _currentSize = len; }
-
-    /**
-     * @since 2.6
-     */
-    public String setCurrentAndReturn(int len) {
-        _currentSize = len;
-        // We can simplify handling here compared to full `contentsAsString()`:
-        if (_segmentSize > 0) { // longer text; call main method
-            return contentsAsString();
-        }
-        // more common case: single segment
-        int currLen = _currentSize;
-        String str = (currLen == 0) ? "" : new String(_currentSegment, 0, currLen);
-        _resultString = str;
-        return str;
-    }
-    
-    public char[] finishCurrentSegment() {
-        if (_segments == null) {
-            _segments = new ArrayList<char[]>();
-        }
-        _hasSegments = true;
-        _segments.add(_currentSegment);
-        int oldLen = _currentSegment.length;
-        _segmentSize += oldLen;
-        _currentSize = 0;
-
-        // Let's grow segments by 50%
-        int newLen = oldLen + (oldLen >> 1);
-        if (newLen < MIN_SEGMENT_LEN) {
-            newLen = MIN_SEGMENT_LEN;
-        } else if (newLen > MAX_SEGMENT_LEN) {
-            newLen = MAX_SEGMENT_LEN;
-        }
-        char[] curr = carr(newLen);
-        _currentSegment = curr;
-        return curr;
-    }
-
-    /**
-     * Method called to expand size of the current segment, to
-     * accommodate for more contiguous content. Usually only
-     * used when parsing tokens like names if even then.
-     */
-    public char[] expandCurrentSegment()
-    {
-        final char[] curr = _currentSegment;
-        // Let's grow by 50% by default
-        final int len = curr.length;
-        int newLen = len + (len >> 1);
-        // but above intended maximum, slow to increase by 25%
-        if (newLen > MAX_SEGMENT_LEN) {
-            newLen = len + (len >> 2);
-        }
-        return (_currentSegment = Arrays.copyOf(curr, newLen));
-    }
-
-    /**
-     * Method called to expand size of the current segment, to
-     * accommodate for more contiguous content. Usually only
-     * used when parsing tokens like names if even then.
-     * 
-     * @param minSize Required minimum strength of the current segment
-     *
-     * @since 2.4.0
-     */
-    public char[] expandCurrentSegment(int minSize) {
-        char[] curr = _currentSegment;
-        if (curr.length >= minSize) return curr;
-        _currentSegment = curr = Arrays.copyOf(curr, minSize);
-        return curr;
-    }
-
-    /*
-    /**********************************************************
-    /* Standard methods:
-    /**********************************************************
-     */
-
-    /**
-     * Note: calling this method may not be as efficient as calling
-     * {@link #contentsAsString}, since it's not guaranteed that resulting
-     * String is cached.
-     */
-    @Override public String toString() { return contentsAsString(); }
-
-    /*
-    /**********************************************************
-    /* Internal methods:
-    /**********************************************************
-     */
-
-    /**
-     * Method called if/when we need to append content when we have been
-     * initialized to use shared buffer.
-     */
-    private void unshare(int needExtra)
-    {
-        int sharedLen = _inputLen;
-        _inputLen = 0;
-        char[] inputBuf = _inputBuffer;
-        _inputBuffer = null;
-        int start = _inputStart;
-        _inputStart = -1;
-
-        // Is buffer big enough, or do we need to reallocate?
-        int needed = sharedLen+needExtra;
-        if (_currentSegment == null || needed > _currentSegment.length) {
-            _currentSegment = buf(needed);
-        }
-        if (sharedLen > 0) {
-            System.arraycopy(inputBuf, start, _currentSegment, 0, sharedLen);
-        }
-        _segmentSize = 0;
-        _currentSize = sharedLen;
-    }
-
-    /**
-     * Method called when current segment is full, to allocate new
-     * segment.
-     */
-    private void expand(int minNewSegmentSize)
-    {
-        // First, let's move current segment to segment list:
-        if (_segments == null) {
-            _segments = new ArrayList<char[]>();
-        }
-        char[] curr = _currentSegment;
-        _hasSegments = true;
-        _segments.add(curr);
-        _segmentSize += curr.length;
-        _currentSize = 0;
-        int oldLen = curr.length;
-        
-        // Let's grow segments by 50% minimum
-        int newLen = oldLen + (oldLen >> 1);
-        if (newLen < MIN_SEGMENT_LEN) {
-            newLen = MIN_SEGMENT_LEN;
-        } else if (newLen > MAX_SEGMENT_LEN) {
-            newLen = MAX_SEGMENT_LEN;
-        }
-        _currentSegment = carr(newLen);
-    }
-
-    private char[] resultArray()
-    {
-        if (_resultString != null) { // Can take a shortcut...
-            return _resultString.toCharArray();
-        }
-        // Do we use shared array?
-        if (_inputStart >= 0) {
-            final int len = _inputLen;
-            if (len < 1) {
-                return NO_CHARS;
-            }
-            final int start = _inputStart;
-            if (start == 0) {
-                return Arrays.copyOf(_inputBuffer, len);
-            }
-            return Arrays.copyOfRange(_inputBuffer, start, start+len);
-        }
-        // nope, not shared
-        int size = size();
-        if (size < 1) {
-            return NO_CHARS;
-        }
-        int offset = 0;
-        final char[] result = carr(size);
-        if (_segments != null) {
-            for (int i = 0, len = _segments.size(); i < len; ++i) {
-                char[] curr = _segments.get(i);
-                int currLen = curr.length;
-                System.arraycopy(curr, 0, result, offset, currLen);
-                offset += currLen;
-            }
-        }
-        System.arraycopy(_currentSegment, 0, result, offset, _currentSize);
-        return result;
-    }
-
-    private char[] carr(int len) { return new char[len]; }
-}
diff --git a/src/test/java/com/fasterxml/jackson/core/util/TestTextBuffer.java b/src/test/java/com/fasterxml/jackson/core/util/TestTextBuffer.java
index 878224ef..0e26d253 100644
--- a/src/test/java/com/fasterxml/jackson/core/util/TestTextBuffer.java
+++ b/src/test/java/com/fasterxml/jackson/core/util/TestTextBuffer.java
@@ -1,8 +1,5 @@
 package com.fasterxml.jackson.core.util;
 
-import com.fasterxml.jackson.core.util.BufferRecycler;
-import com.fasterxml.jackson.core.util.TextBuffer;
-
 public class TestTextBuffer
     extends com.fasterxml.jackson.core.BaseTest
 {
@@ -12,33 +9,33 @@ public class TestTextBuffer
      */
     public void testSimple()
     {
-        TextBuffer tb = new TextBuffer(new BufferRecycler());
-        tb.append('a');
-        tb.append(new char[] { 'X', 'b' }, 1, 1);
-        tb.append("c", 0, 1);
-        assertEquals(3, tb.contentsAsArray().length);
+        SegmentedTextBuffer tb = new SegmentedTextBuffer(new BufferRecycler());
+        tb.appendChar('a');
+        tb.appendChar(new char[] { 'X', 'b' }, 1, 1);
+        tb.appendChar("c", 0, 1);
+        assertEquals(3, tb.contentsAsCharArray().length);
         assertEquals("abc", tb.toString());
 
-        assertNotNull(tb.expandCurrentSegment());
+        assertNotNull(tb.growCurrentSegment());
     }
 
     public void testLonger()
     {
-        TextBuffer tb = new TextBuffer(new BufferRecycler());
+        SegmentedTextBuffer tb = new SegmentedTextBuffer(new BufferRecycler());
         for (int i = 0; i < 2000; ++i) {
-            tb.append("abc", 0, 3);
+            tb.appendChar("abc", 0, 3);
         }
-        String str = tb.contentsAsString();
+        String str = tb.getContentsAsString();
         assertEquals(6000, str.length());
-        assertEquals(6000, tb.contentsAsArray().length);
+        assertEquals(6000, tb.contentsAsCharArray().length);
 
-        tb.resetWithShared(new char[] { 'a' }, 0, 1);
+        tb.resetWithSharedBuffer(new char[] { 'a' }, 0, 1);
         assertEquals(1, tb.toString().length());
     }
 
       public void testLongAppend()
       {
-          final int len = TextBuffer.MAX_SEGMENT_LEN * 3 / 2;
+          final int len = SegmentedTextBuffer.MAX_SEGMENT_LENGTH * 3 / 2;
           StringBuilder sb = new StringBuilder(len);
           for (int i = 0; i < len; ++i) {
               sb.append('x');
@@ -47,31 +44,31 @@ public class TestTextBuffer
          final String EXP = "a" + STR + "c";
  
          // ok: first test with String:
-         TextBuffer tb = new TextBuffer(new BufferRecycler());
-         tb.append('a');
-         tb.append(STR, 0, len);
-         tb.append('c');
-         assertEquals(len+2, tb.size());
-         assertEquals(EXP, tb.contentsAsString());
+         SegmentedTextBuffer tb = new SegmentedTextBuffer(new BufferRecycler());
+         tb.appendChar('a');
+         tb.appendChar(STR, 0, len);
+         tb.appendChar('c');
+         assertEquals(len+2, tb.length());
+         assertEquals(EXP, tb.getContentsAsString());
  
          // then char[]
-         tb = new TextBuffer(new BufferRecycler());
-         tb.append('a');
+         tb = new SegmentedTextBuffer(new BufferRecycler());
+         tb.appendChar('a');
          tb.append(STR.toCharArray(), 0, len);
-         tb.append('c');
-         assertEquals(len+2, tb.size());
-         assertEquals(EXP, tb.contentsAsString());
+         tb.appendChar('c');
+         assertEquals(len+2, tb.length());
+         assertEquals(EXP, tb.getContentsAsString());
       }
 
       // [Core#152]
       public void testExpand()
       {
-          TextBuffer tb = new TextBuffer(new BufferRecycler());
+          SegmentedTextBuffer tb = new SegmentedTextBuffer(new BufferRecycler());
           char[] buf = tb.getCurrentSegment();
 
           while (buf.length < 500 * 1000) {
               char[] old = buf;
-              buf = tb.expandCurrentSegment();
+              buf = tb.growCurrentSegment();
               if (old.length >= buf.length) {
                   fail("Expected buffer of "+old.length+" to expand, did not, length now "+buf.length);
               }

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

file="/home/jackson-core/pom.xml"
old_version="2.15.0-rc2-SNAPSHOT"
new_version="2.15.5-SNAPSHOT"
sed -i "s/$old_version/$new_version/g" "$file"

mvn clean test -Dmaven.test.skip=false -DfailIfNoTests=false || true
