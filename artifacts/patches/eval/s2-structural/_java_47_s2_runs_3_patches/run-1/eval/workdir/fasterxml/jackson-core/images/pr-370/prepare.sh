#!/bin/bash
set -e

cd /home/jackson-core
git reset --hard
bash /home/check_git_changes.sh
git checkout f42556388bb8ad547a55e4ee7cfb52a99f670186

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/com/fasterxml/jackson/core/json/ReaderBasedJsonParser.java b/src/main/java/com/fasterxml/jackson/core/io/ReaderBasedJsonParser.java
similarity index 96%
rename from src/main/java/com/fasterxml/jackson/core/json/ReaderBasedJsonParser.java
rename to src/main/java/com/fasterxml/jackson/core/io/ReaderBasedJsonParser.java
index a0014052..1816e30f 100644
--- a/src/main/java/com/fasterxml/jackson/core/json/ReaderBasedJsonParser.java
+++ b/src/main/java/com/fasterxml/jackson/core/io/ReaderBasedJsonParser.java
@@ -1,11 +1,9 @@
-package com.fasterxml.jackson.core.json;
+package com.fasterxml.jackson.core.io;
 
 import java.io.*;
 
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.core.base.ParserBase;
-import com.fasterxml.jackson.core.io.CharTypes;
-import com.fasterxml.jackson.core.io.IOContext;
 import com.fasterxml.jackson.core.sym.CharsToNameCanonicalizer;
 import com.fasterxml.jackson.core.util.*;
 
@@ -104,562 +102,330 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
     /**********************************************************
      */
 
-    /**
-     * Method called when caller wants to provide input buffer directly,
-     * and it may or may not be recyclable use standard recycle context.
-     *
-     * @since 2.4
+    /*
+    /**********************************************************
+    /* Base method defs, overrides
+    /**********************************************************
      */
-    public ReaderBasedJsonParser(IOContext ctxt, int features, Reader r,
-            ObjectCodec codec, CharsToNameCanonicalizer st,
-            char[] inputBuffer, int start, int end,
-            boolean bufferRecyclable)
-    {
-        super(ctxt, features);
-        _reader = r;
-        _inputBuffer = inputBuffer;
-        _inputPtr = start;
-        _inputEnd = end;
-        _objectCodec = codec;
-        _symbols = st;
-        _hashSeed = st.hashSeed();
-        _bufferRecyclable = bufferRecyclable;
-    }
 
-    /**
-     * Method called when input comes as a {@link java.io.Reader}, and buffer allocation
-     * can be done using default mechanism.
+    /*
+    /**********************************************************
+    /* Low-level access, supporting
+    /**********************************************************
      */
-    public ReaderBasedJsonParser(IOContext ctxt, int features, Reader r,
-        ObjectCodec codec, CharsToNameCanonicalizer st)
-    {
-        super(ctxt, features);
-        _reader = r;
-        _inputBuffer = ctxt.allocTokenBuffer();
-        _inputPtr = 0;
-        _inputEnd = 0;
-        _objectCodec = codec;
-        _symbols = st;
-        _hashSeed = st.hashSeed();
-        _bufferRecyclable = true;
-    }
 
     /*
     /**********************************************************
-    /* Base method defs, overrides
+    /* Public API, data access
     /**********************************************************
      */
 
-    @Override public ObjectCodec getCodec() { return _objectCodec; }
-    @Override public void setCodec(ObjectCodec c) { _objectCodec = c; }
-
-    @Override
-    public int releaseBuffered(Writer w) throws IOException {
-        int count = _inputEnd - _inputPtr;
-        if (count < 1) { return 0; }
-        // let's just advance ptr to end
-        int origPtr = _inputPtr;
-        w.write(_inputBuffer, origPtr, count);
-        return count;
-    }
-
-    @Override public Object getInputSource() { return _reader; }
-
-    @Deprecated // since 2.8
-    protected char getNextChar(String eofMsg) throws IOException {
-        return getNextChar(eofMsg, null);
-    }
-    
-    protected char getNextChar(String eofMsg, JsonToken forToken) throws IOException {
-        if (_inputPtr >= _inputEnd) {
-            if (!_loadMore()) {
-                _reportInvalidEOF(eofMsg, forToken);
-            }
-        }
-        return _inputBuffer[_inputPtr++];
-    }
+    // // // Let's override default impls for improved performance
 
-    @Override
-    protected void _closeInput() throws IOException {
-        /* 25-Nov-2008, tatus: As per [JACKSON-16] we are not to call close()
-         *   on the underlying Reader, unless we "own" it, or auto-closing
-         *   feature is enabled.
-         *   One downside is that when using our optimized
-         *   Reader (granted, we only do that for UTF-32...) this
-         *   means that buffer recycling won't work correctly.
-         */
-        if (_reader != null) {
-            if (_ioContext.isResourceManaged() || isEnabled(Feature.AUTO_CLOSE_SOURCE)) {
-                _reader.close();
-            }
-            _reader = null;
-        }
-    }
+    /*
+    /**********************************************************
+    /* Public API, traversal
+    /**********************************************************
+     */
 
-    /**
-     * Method called to release internal buffers owned by the base
-     * reader. This may be called along with {@link #_closeInput} (for
-     * example, when explicitly closing this reader instance), or
-     * separately (if need be).
+    /*
+    /**********************************************************
+    /* Public API, nextXxx() overrides
+    /**********************************************************
      */
-    @Override
-    protected void _releaseBuffers() throws IOException {
-        super._releaseBuffers();
-        // merge new symbols, if any
-        _symbols.release();
-        // and release buffers, if they are recyclable ones
-        if (_bufferRecyclable) {
-            char[] buf = _inputBuffer;
-            if (buf != null) {
-                _inputBuffer = null;
-                _ioContext.releaseTokenBuffer(buf);
-            }
-        }
-    }
 
     /*
     /**********************************************************
-    /* Low-level access, supporting
+    /* Internal methods, number parsing
     /**********************************************************
      */
 
-    protected void _loadMoreGuaranteed() throws IOException {
-        if (!_loadMore()) { _reportInvalidEOF(); }
-    }
-    
-    protected boolean _loadMore() throws IOException
-    {
-        final int bufSize = _inputEnd;
+    /*
+    /**********************************************************
+    /* Internal methods, secondary parsing
+    /**********************************************************
+     */
 
-        _currInputProcessed += bufSize;
-        _currInputRowStart -= bufSize;
+    /*
+    /**********************************************************
+    /* Internal methods, other parsing
+    /**********************************************************
+     */
 
-        // 26-Nov-2015, tatu: Since name-offset requires it too, must offset
-        //   this increase to avoid "moving" name-offset, resulting most likely
-        //   in negative value, which is fine as combine value remains unchanged.
-        _nameStartOffset -= bufSize;
+    /*
+    /**********************************************************
+    /* Binary access
+    /**********************************************************
+     */
 
-        if (_reader != null) {
-            int count = _reader.read(_inputBuffer, 0, _inputBuffer.length);
-            if (count > 0) {
-                _inputPtr = 0;
-                _inputEnd = count;
-                return true;
-            }
-            // End of input
-            _closeInput();
-            // Should never return 0, so let's fail
-            if (count == 0) {
-                throw new IOException("Reader returned 0 characters when trying to read "+_inputEnd);
-            }
-        }
-        return false;
-    }
+    /*
+    /**********************************************************
+    /* Internal methods, location updating (refactored in 2.7)
+    /**********************************************************
+     */
 
     /*
     /**********************************************************
-    /* Public API, data access
+    /* Error reporting
     /**********************************************************
      */
 
-    /**
-     * Method for accessing textual representation of the current event;
-     * if no current event (before first call to {@link #nextToken}, or
-     * after encountering end-of-input), returns null.
-     * Method can be called for any event.
+    /*
+    /**********************************************************
+    /* Internal methods, other
+    /**********************************************************
      */
-    @Override
-    public final String getText() throws IOException
-    {
-        JsonToken t = _currToken;
-        if (t == JsonToken.VALUE_STRING) {
-            if (_tokenIncomplete) {
-                _tokenIncomplete = false;
-                _finishString(); // only strings can be incomplete
-            }
-            return _textBuffer.contentsAsString();
-        }
-        return _getText2(t);
-    }
 
-    @Override // since 2.8
-    public int getText(Writer writer) throws IOException
+    @Override public void setCodec(ObjectCodec c) { _objectCodec = c; }@Override
+    public int releaseBuffered(Writer w) throws IOException {
+        int count = _inputEnd - _inputPtr;
+        if (count < 1) { return 0; }
+        // let's just advance ptr to end
+        int origPtr = _inputPtr;
+        w.write(_inputBuffer, origPtr, count);
+        return count;
+    }@Override
+    public int readBinaryValue(Base64Variant b64variant, OutputStream out) throws IOException
     {
-        JsonToken t = _currToken;
-        if (t == JsonToken.VALUE_STRING) {
-            if (_tokenIncomplete) {
-                _tokenIncomplete = false;
-                _finishString(); // only strings can be incomplete
-            }
-            return _textBuffer.contentsToWriter(writer);
-        }
-        if (t == JsonToken.FIELD_NAME) {
-            String n = _parsingContext.getCurrentName();
-            writer.write(n);
-            return n.length();
+        // if we have already read the token, just use whatever we may have
+        if (!_tokenIncomplete || _currToken != JsonToken.VALUE_STRING) {
+            byte[] b = getBinaryValue(b64variant);
+            out.write(b);
+            return b.length;
         }
-        if (t != null) {
-            if (t.isNumeric()) {
-                return _textBuffer.contentsToWriter(writer);
-            }
-            char[] ch = t.asCharArray();
-            writer.write(ch);
-            return ch.length;
+        // otherwise do "real" incremental parsing...
+        byte[] buf = _ioContext.allocBase64Buffer();
+        try {
+            return _readBinary(b64variant, out, buf);
+        } finally {
+            _ioContext.releaseBase64Buffer(buf);
         }
-        return 0;
-    }
-    
-    // // // Let's override default impls for improved performance
-
-    // @since 2.1
+    } /**
+     * @return Next token from the stream, if any found, or null
+     *   to indicate end-of-input
+     */
     @Override
-    public final String getValueAsString() throws IOException
+    public final JsonToken nextToken() throws IOException
     {
-        if (_currToken == JsonToken.VALUE_STRING) {
-            if (_tokenIncomplete) {
-                _tokenIncomplete = false;
-                _finishString(); // only strings can be incomplete
-            }
-            return _textBuffer.contentsAsString();
-        }
+        /* First: field names are special -- we will always tokenize
+         * (part of) value along with field name to simplify
+         * state handling. If so, can and need to use secondary token:
+         */
         if (_currToken == JsonToken.FIELD_NAME) {
-            return getCurrentName();
-        }
-        return super.getValueAsString(null);
-    }
-
-    // @since 2.1
-    @Override
-    public final String getValueAsString(String defValue) throws IOException {
-        if (_currToken == JsonToken.VALUE_STRING) {
-            if (_tokenIncomplete) {
-                _tokenIncomplete = false;
-                _finishString(); // only strings can be incomplete
-            }
-            return _textBuffer.contentsAsString();
+            return _nextAfterName();
         }
-        if (_currToken == JsonToken.FIELD_NAME) {
-            return getCurrentName();
+        // But if we didn't already have a name, and (partially?) decode number,
+        // need to ensure no numeric information is leaked
+        _numTypesValid = NR_UNKNOWN;
+        if (_tokenIncomplete) {
+            _skipString(); // only strings can be partial
         }
-        return super.getValueAsString(defValue);
-    }
-
-    protected final String _getText2(JsonToken t) {
-        if (t == null) {
-            return null;
+        int i = _skipWSOrEnd();
+        if (i < 0) { // end-of-input
+            // Should actually close/release things
+            // like input source, symbol table and recyclable buffers now.
+            close();
+            return (_currToken = null);
         }
-        switch (t.id()) {
-        case ID_FIELD_NAME:
-            return _parsingContext.getCurrentName();
+        // clear any data retained so far
+        _binaryValue = null;
 
-        case ID_STRING:
-            // fall through
-        case ID_NUMBER_INT:
-        case ID_NUMBER_FLOAT:
-            return _textBuffer.contentsAsString();
-        default:
-            return t.asString();
+        // Closing scope?
+        if (i == INT_RBRACKET || i == INT_RCURLY) {
+            _closeScope(i);
+            return _currToken;
         }
-    }
 
-    @Override
-    public final char[] getTextCharacters() throws IOException
-    {
-        if (_currToken != null) { // null only before/after document
-            switch (_currToken.id()) {
-            case ID_FIELD_NAME:
-                if (!_nameCopied) {
-                    String name = _parsingContext.getCurrentName();
-                    int nameLen = name.length();
-                    if (_nameCopyBuffer == null) {
-                        _nameCopyBuffer = _ioContext.allocNameCopyBuffer(nameLen);
-                    } else if (_nameCopyBuffer.length < nameLen) {
-                        _nameCopyBuffer = new char[nameLen];
-                    }
-                    name.getChars(0, nameLen, _nameCopyBuffer, 0);
-                    _nameCopied = true;
-                }
-                return _nameCopyBuffer;
-            case ID_STRING:
-                if (_tokenIncomplete) {
-                    _tokenIncomplete = false;
-                    _finishString(); // only strings can be incomplete
+        // Nope: do we then expect a comma?
+        if (_parsingContext.expectComma()) {
+            i = _skipComma(i);
+
+            // Was that a trailing comma?
+            if ((_features & FEAT_MASK_TRAILING_COMMA) != 0) {
+                if ((i == INT_RBRACKET) || (i == INT_RCURLY)) {
+                    _closeScope(i);
+                    return _currToken;
                 }
-                // fall through
-            case ID_NUMBER_INT:
-            case ID_NUMBER_FLOAT:
-                return _textBuffer.getTextBuffer();
-            default:
-                return _currToken.asCharArray();
             }
         }
-        return null;
-    }
 
-    @Override
-    public final int getTextLength() throws IOException
-    {
-        if (_currToken != null) { // null only before/after document
-            switch (_currToken.id()) {
-            case ID_FIELD_NAME:
-                return _parsingContext.getCurrentName().length();
-            case ID_STRING:
-                if (_tokenIncomplete) {
-                    _tokenIncomplete = false;
-                    _finishString(); // only strings can be incomplete
-                }
-                // fall through
-            case ID_NUMBER_INT:
-            case ID_NUMBER_FLOAT:
-                return _textBuffer.size();
-            default:
-                return _currToken.asCharArray().length;
+        /* And should we now have a name? Always true for Object contexts, since
+         * the intermediate 'expect-value' state is never retained.
+         */
+        boolean inObject = _parsingContext.inObject();
+        if (inObject) {
+            // First, field name itself:
+            _updateNameLocation();
+            String name = (i == INT_QUOTE) ? _parseName() : _handleOddName(i);
+            _parsingContext.setCurrentName(name);
+            _currToken = JsonToken.FIELD_NAME;
+            i = _skipColon();
+        }
+        _updateLocation();
+
+        // Ok: we must have a value... what is it?
+
+        JsonToken t;
+
+        switch (i) {
+        case '"':
+            _tokenIncomplete = true;
+            t = JsonToken.VALUE_STRING;
+            break;
+        case '[':
+            if (!inObject) {
+                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            }
+            t = JsonToken.START_ARRAY;
+            break;
+        case '{':
+            if (!inObject) {
+                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
             }
+            t = JsonToken.START_OBJECT;
+            break;
+        case '}':
+            // Error: } is not valid at this point; valid closers have
+            // been handled earlier
+            _reportUnexpectedChar(i, "expected a value");
+        case 't':
+            _matchTrue();
+            t = JsonToken.VALUE_TRUE;
+            break;
+        case 'f':
+            _matchFalse();
+            t = JsonToken.VALUE_FALSE;
+            break;
+        case 'n':
+            _matchNull();
+            t = JsonToken.VALUE_NULL;
+            break;
+
+        case '-':
+            /* Should we have separate handling for plus? Although
+             * it is not allowed per se, it may be erroneously used,
+             * and could be indicate by a more specific error message.
+             */
+            t = _parseNegNumber();
+            break;
+        case '0':
+        case '1':
+        case '2':
+        case '3':
+        case '4':
+        case '5':
+        case '6':
+        case '7':
+        case '8':
+        case '9':
+            t = _parsePosNumber(i);
+            break;
+        default:
+            t = _handleOddValue(i);
+            break;
         }
-        return 0;
-    }
 
+        if (inObject) {
+            _nextToken = t;
+            return _currToken;
+        }
+        _currToken = t;
+        return t;
+    }// note: identical to one in UTF8StreamJsonParser
     @Override
-    public final int getTextOffset() throws IOException
+    public final String nextTextValue() throws IOException
     {
-        // Most have offset of 0, only some may have other values:
-        if (_currToken != null) {
-            switch (_currToken.id()) {
-            case ID_FIELD_NAME:
-                return 0;
-            case ID_STRING:
+        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
+            _nameCopied = false;
+            JsonToken t = _nextToken;
+            _nextToken = null;
+            _currToken = t;
+            if (t == JsonToken.VALUE_STRING) {
                 if (_tokenIncomplete) {
                     _tokenIncomplete = false;
-                    _finishString(); // only strings can be incomplete
+                    _finishString();
                 }
-                // fall through
-            case ID_NUMBER_INT:
-            case ID_NUMBER_FLOAT:
-                return _textBuffer.getTextOffset();
-            default:
+                return _textBuffer.contentsAsString();
+            }
+            if (t == JsonToken.START_ARRAY) {
+                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            } else if (t == JsonToken.START_OBJECT) {
+                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
             }
+            return null;
         }
-        return 0;
-    }
-
+        // !!! TODO: optimize this case as well
+        return (nextToken() == JsonToken.VALUE_STRING) ? getText() : null;
+    }// note: identical to one in Utf8StreamParser
     @Override
-    public byte[] getBinaryValue(Base64Variant b64variant) throws IOException
+    public final long nextLongValue(long defaultValue) throws IOException
     {
-        if ((_currToken == JsonToken.VALUE_EMBEDDED_OBJECT) && (_binaryValue != null)) {
-            return _binaryValue;
-        }
-        if (_currToken != JsonToken.VALUE_STRING) {
-            _reportError("Current token ("+_currToken+") not VALUE_STRING or VALUE_EMBEDDED_OBJECT, can not access as binary");
-        }
-        // To ensure that we won't see inconsistent data, better clear up state
-        if (_tokenIncomplete) {
-            try {
-                _binaryValue = _decodeBase64(b64variant);
-            } catch (IllegalArgumentException iae) {
-                throw _constructError("Failed to decode VALUE_STRING as base64 ("+b64variant+"): "+iae.getMessage());
+        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
+            _nameCopied = false;
+            JsonToken t = _nextToken;
+            _nextToken = null;
+            _currToken = t;
+            if (t == JsonToken.VALUE_NUMBER_INT) {
+                return getLongValue();
             }
-            /* let's clear incomplete only now; allows for accessing other
-             * textual content in error cases
-             */
-            _tokenIncomplete = false;
-        } else { // may actually require conversion...
-            if (_binaryValue == null) {
-                @SuppressWarnings("resource")
-                ByteArrayBuilder builder = _getByteArrayBuilder();
-                _decodeBase64(getText(), builder, b64variant);
-                _binaryValue = builder.toByteArray();
+            if (t == JsonToken.START_ARRAY) {
+                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            } else if (t == JsonToken.START_OBJECT) {
+                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
             }
+            return defaultValue;
         }
-        return _binaryValue;
-    }
-
+        // !!! TODO: optimize this case as well
+        return (nextToken() == JsonToken.VALUE_NUMBER_INT) ? getLongValue() : defaultValue;
+    }// note: identical to one in Utf8StreamParser
     @Override
-    public int readBinaryValue(Base64Variant b64variant, OutputStream out) throws IOException
+    public final int nextIntValue(int defaultValue) throws IOException
     {
-        // if we have already read the token, just use whatever we may have
-        if (!_tokenIncomplete || _currToken != JsonToken.VALUE_STRING) {
-            byte[] b = getBinaryValue(b64variant);
-            out.write(b);
-            return b.length;
+        if (_currToken == JsonToken.FIELD_NAME) {
+            _nameCopied = false;
+            JsonToken t = _nextToken;
+            _nextToken = null;
+            _currToken = t;
+            if (t == JsonToken.VALUE_NUMBER_INT) {
+                return getIntValue();
+            }
+            if (t == JsonToken.START_ARRAY) {
+                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            } else if (t == JsonToken.START_OBJECT) {
+                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            }
+            return defaultValue;
         }
-        // otherwise do "real" incremental parsing...
-        byte[] buf = _ioContext.allocBase64Buffer();
-        try {
-            return _readBinary(b64variant, out, buf);
-        } finally {
-            _ioContext.releaseBase64Buffer(buf);
-        }
-    }
-
-    protected int _readBinary(Base64Variant b64variant, OutputStream out, byte[] buffer) throws IOException
-    {
-        int outputPtr = 0;
-        final int outputEnd = buffer.length - 3;
-        int outputCount = 0;
-
-        while (true) {
-            // first, we'll skip preceding white space, if any
-            char ch;
-            do {
-                if (_inputPtr >= _inputEnd) {
-                    _loadMoreGuaranteed();
-                }
-                ch = _inputBuffer[_inputPtr++];
-            } while (ch <= INT_SPACE);
-            int bits = b64variant.decodeBase64Char(ch);
-            if (bits < 0) { // reached the end, fair and square?
-                if (ch == '"') {
-                    break;
-                }
-                bits = _decodeBase64Escape(b64variant, ch, 0);
-                if (bits < 0) { // white space to skip
-                    continue;
-                }
-            }
-
-            // enough room? If not, flush
-            if (outputPtr > outputEnd) {
-                outputCount += outputPtr;
-                out.write(buffer, 0, outputPtr);
-                outputPtr = 0;
-            }
-
-            int decodedData = bits;
-
-            // then second base64 char; can't get padding yet, nor ws
-
-            if (_inputPtr >= _inputEnd) {
-                _loadMoreGuaranteed();
-            }
-            ch = _inputBuffer[_inputPtr++];
-            bits = b64variant.decodeBase64Char(ch);
-            if (bits < 0) {
-                bits = _decodeBase64Escape(b64variant, ch, 1);
-            }
-            decodedData = (decodedData << 6) | bits;
-
-            // third base64 char; can be padding, but not ws
-            if (_inputPtr >= _inputEnd) {
-                _loadMoreGuaranteed();
-            }
-            ch = _inputBuffer[_inputPtr++];
-            bits = b64variant.decodeBase64Char(ch);
-
-            // First branch: can get padding (-> 1 byte)
-            if (bits < 0) {
-                if (bits != Base64Variant.BASE64_VALUE_PADDING) {
-                    // as per [JACKSON-631], could also just be 'missing'  padding
-                    if (ch == '"' && !b64variant.usesPadding()) {
-                        decodedData >>= 4;
-                        buffer[outputPtr++] = (byte) decodedData;
-                        break;
-                    }
-                    bits = _decodeBase64Escape(b64variant, ch, 2);
-                }
-                if (bits == Base64Variant.BASE64_VALUE_PADDING) {
-                    // Ok, must get padding
-                    if (_inputPtr >= _inputEnd) {
-                        _loadMoreGuaranteed();
-                    }
-                    ch = _inputBuffer[_inputPtr++];
-                    if (!b64variant.usesPaddingChar(ch)) {
-                        throw reportInvalidBase64Char(b64variant, ch, 3, "expected padding character '"+b64variant.getPaddingChar()+"'");
-                    }
-                    // Got 12 bits, only need 8, need to shift
-                    decodedData >>= 4;
-                    buffer[outputPtr++] = (byte) decodedData;
-                    continue;
-                }
-            }
-            // Nope, 2 or 3 bytes
-            decodedData = (decodedData << 6) | bits;
-            // fourth and last base64 char; can be padding, but not ws
-            if (_inputPtr >= _inputEnd) {
-                _loadMoreGuaranteed();
-            }
-            ch = _inputBuffer[_inputPtr++];
-            bits = b64variant.decodeBase64Char(ch);
-            if (bits < 0) {
-                if (bits != Base64Variant.BASE64_VALUE_PADDING) {
-                    // as per [JACKSON-631], could also just be 'missing'  padding
-                    if (ch == '"' && !b64variant.usesPadding()) {
-                        decodedData >>= 2;
-                        buffer[outputPtr++] = (byte) (decodedData >> 8);
-                        buffer[outputPtr++] = (byte) decodedData;
-                        break;
-                    }
-                    bits = _decodeBase64Escape(b64variant, ch, 3);
-                }
-                if (bits == Base64Variant.BASE64_VALUE_PADDING) {
-                    /* With padding we only get 2 bytes; but we have
-                     * to shift it a bit so it is identical to triplet
-                     * case with partial output.
-                     * 3 chars gives 3x6 == 18 bits, of which 2 are
-                     * dummies, need to discard:
-                     */
-                    decodedData >>= 2;
-                    buffer[outputPtr++] = (byte) (decodedData >> 8);
-                    buffer[outputPtr++] = (byte) decodedData;
-                    continue;
-                }
-            }
-            // otherwise, our triplet is now complete
-            decodedData = (decodedData << 6) | bits;
-            buffer[outputPtr++] = (byte) (decodedData >> 16);
-            buffer[outputPtr++] = (byte) (decodedData >> 8);
-            buffer[outputPtr++] = (byte) decodedData;
-        }
-        _tokenIncomplete = false;
-        if (outputPtr > 0) {
-            outputCount += outputPtr;
-            out.write(buffer, 0, outputPtr);
-        }
-        return outputCount;
-    }
-
-    /*
-    /**********************************************************
-    /* Public API, traversal
-    /**********************************************************
-     */
-
-    /**
-     * @return Next token from the stream, if any found, or null
-     *   to indicate end-of-input
-     */
+        // !!! TODO: optimize this case as well
+        return (nextToken() == JsonToken.VALUE_NUMBER_INT) ? getIntValue() : defaultValue;
+    }// Implemented since 2.7
     @Override
-    public final JsonToken nextToken() throws IOException
+    public boolean nextFieldName(SerializableString sstr) throws IOException
     {
-        /* First: field names are special -- we will always tokenize
-         * (part of) value along with field name to simplify
-         * state handling. If so, can and need to use secondary token:
-         */
+        // // // Note: most of code below is copied from nextToken()
+
+        _numTypesValid = NR_UNKNOWN;
         if (_currToken == JsonToken.FIELD_NAME) {
-            return _nextAfterName();
+            _nextAfterName();
+            return false;
         }
-        // But if we didn't already have a name, and (partially?) decode number,
-        // need to ensure no numeric information is leaked
-        _numTypesValid = NR_UNKNOWN;
         if (_tokenIncomplete) {
-            _skipString(); // only strings can be partial
+            _skipString();
         }
         int i = _skipWSOrEnd();
-        if (i < 0) { // end-of-input
-            // Should actually close/release things
-            // like input source, symbol table and recyclable buffers now.
+        if (i < 0) {
             close();
-            return (_currToken = null);
+            _currToken = null;
+            return false;
         }
-        // clear any data retained so far
         _binaryValue = null;
 
         // Closing scope?
         if (i == INT_RBRACKET || i == INT_RCURLY) {
             _closeScope(i);
-            return _currToken;
+            return false;
         }
 
-        // Nope: do we then expect a comma?
         if (_parsingContext.expectComma()) {
             i = _skipComma(i);
 
@@ -667,207 +433,50 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
             if ((_features & FEAT_MASK_TRAILING_COMMA) != 0) {
                 if ((i == INT_RBRACKET) || (i == INT_RCURLY)) {
                     _closeScope(i);
-                    return _currToken;
+                    return false;
                 }
             }
         }
 
-        /* And should we now have a name? Always true for Object contexts, since
-         * the intermediate 'expect-value' state is never retained.
-         */
-        boolean inObject = _parsingContext.inObject();
-        if (inObject) {
-            // First, field name itself:
-            _updateNameLocation();
-            String name = (i == INT_QUOTE) ? _parseName() : _handleOddName(i);
-            _parsingContext.setCurrentName(name);
-            _currToken = JsonToken.FIELD_NAME;
-            i = _skipColon();
+        if (!_parsingContext.inObject()) {
+            _updateLocation();
+            _nextTokenNotInObject(i);
+            return false;
         }
-        _updateLocation();
-
-        // Ok: we must have a value... what is it?
 
-        JsonToken t;
+        _updateNameLocation();
+        if (i == INT_QUOTE) {
+            // when doing literal match, must consider escaping:
+            char[] nameChars = sstr.asQuotedChars();
+            final int len = nameChars.length;
 
-        switch (i) {
-        case '"':
-            _tokenIncomplete = true;
-            t = JsonToken.VALUE_STRING;
-            break;
-        case '[':
-            if (!inObject) {
-                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
-            }
-            t = JsonToken.START_ARRAY;
-            break;
-        case '{':
-            if (!inObject) {
-                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            // Require 4 more bytes for faster skipping of colon that follows name
+            if ((_inputPtr + len + 4) < _inputEnd) { // maybe...
+                // first check length match by
+                final int end = _inputPtr+len;
+                if (_inputBuffer[end] == '"') {
+                    int offset = 0;
+                    int ptr = _inputPtr;
+                    while (true) {
+                        if (ptr == end) { // yes, match!
+                            _parsingContext.setCurrentName(sstr.getValue());
+                            _isNextTokenNameYes(_skipColonFast(ptr+1));
+                            return true;
+                        }
+                        if (nameChars[offset] != _inputBuffer[ptr]) {
+                            break;
+                        }
+                        ++offset;
+                        ++ptr;
+                    }
+                }
             }
-            t = JsonToken.START_OBJECT;
-            break;
-        case '}':
-            // Error: } is not valid at this point; valid closers have
-            // been handled earlier
-            _reportUnexpectedChar(i, "expected a value");
-        case 't':
-            _matchTrue();
-            t = JsonToken.VALUE_TRUE;
-            break;
-        case 'f':
-            _matchFalse();
-            t = JsonToken.VALUE_FALSE;
-            break;
-        case 'n':
-            _matchNull();
-            t = JsonToken.VALUE_NULL;
-            break;
-
-        case '-':
-            /* Should we have separate handling for plus? Although
-             * it is not allowed per se, it may be erroneously used,
-             * and could be indicate by a more specific error message.
-             */
-            t = _parseNegNumber();
-            break;
-        case '0':
-        case '1':
-        case '2':
-        case '3':
-        case '4':
-        case '5':
-        case '6':
-        case '7':
-        case '8':
-        case '9':
-            t = _parsePosNumber(i);
-            break;
-        default:
-            t = _handleOddValue(i);
-            break;
-        }
-
-        if (inObject) {
-            _nextToken = t;
-            return _currToken;
-        }
-        _currToken = t;
-        return t;
-    }
-
-    private final JsonToken _nextAfterName()
-    {
-        _nameCopied = false; // need to invalidate if it was copied
-        JsonToken t = _nextToken;
-        _nextToken = null;
-
-// !!! 16-Nov-2015, tatu: TODO: fix [databind#37], copy next location to current here
-        
-        // Also: may need to start new context?
-        if (t == JsonToken.START_ARRAY) {
-            _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
-        } else if (t == JsonToken.START_OBJECT) {
-            _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
-        }
-        return (_currToken = t);
-    }
-
-    @Override
-    public void finishToken() throws IOException {
-        if (_tokenIncomplete) {
-            _tokenIncomplete = false;
-            _finishString(); // only strings can be incomplete
-        }
-    }
-
-    /*
-    /**********************************************************
-    /* Public API, nextXxx() overrides
-    /**********************************************************
-     */
-
-    // Implemented since 2.7
-    @Override
-    public boolean nextFieldName(SerializableString sstr) throws IOException
-    {
-        // // // Note: most of code below is copied from nextToken()
-
-        _numTypesValid = NR_UNKNOWN;
-        if (_currToken == JsonToken.FIELD_NAME) {
-            _nextAfterName();
-            return false;
-        }
-        if (_tokenIncomplete) {
-            _skipString();
-        }
-        int i = _skipWSOrEnd();
-        if (i < 0) {
-            close();
-            _currToken = null;
-            return false;
-        }
-        _binaryValue = null;
-
-        // Closing scope?
-        if (i == INT_RBRACKET || i == INT_RCURLY) {
-            _closeScope(i);
-            return false;
-        }
-
-        if (_parsingContext.expectComma()) {
-            i = _skipComma(i);
-
-            // Was that a trailing comma?
-            if ((_features & FEAT_MASK_TRAILING_COMMA) != 0) {
-                if ((i == INT_RBRACKET) || (i == INT_RCURLY)) {
-                    _closeScope(i);
-                    return false;
-                }
-            }
-        }
-
-        if (!_parsingContext.inObject()) {
-            _updateLocation();
-            _nextTokenNotInObject(i);
-            return false;
-        }
-
-        _updateNameLocation();
-        if (i == INT_QUOTE) {
-            // when doing literal match, must consider escaping:
-            char[] nameChars = sstr.asQuotedChars();
-            final int len = nameChars.length;
-
-            // Require 4 more bytes for faster skipping of colon that follows name
-            if ((_inputPtr + len + 4) < _inputEnd) { // maybe...
-                // first check length match by
-                final int end = _inputPtr+len;
-                if (_inputBuffer[end] == '"') {
-                    int offset = 0;
-                    int ptr = _inputPtr;
-                    while (true) {
-                        if (ptr == end) { // yes, match!
-                            _parsingContext.setCurrentName(sstr.getValue());
-                            _isNextTokenNameYes(_skipColonFast(ptr+1));
-                            return true;
-                        }
-                        if (nameChars[offset] != _inputBuffer[ptr]) {
-                            break;
-                        }
-                        ++offset;
-                        ++ptr;
-                    }
-                }
-            }
-        }
-        return _isNextTokenNameMaybe(i, sstr.getValue());
-    }
-
-    @Override
-    public String nextFieldName() throws IOException
-    {
-        // // // Note: this is almost a verbatim copy of nextToken() (minus comments)
+        }
+        return _isNextTokenNameMaybe(i, sstr.getValue());
+    }@Override
+    public String nextFieldName() throws IOException
+    {
+        // // // Note: this is almost a verbatim copy of nextToken() (minus comments)
 
         _numTypesValid = NR_UNKNOWN;
         if (_currToken == JsonToken.FIELD_NAME) {
@@ -923,7 +532,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
             _nextToken = JsonToken.VALUE_STRING;
             return name;
         }
-        
+
         // Ok: we must have a value... what is it?
 
         JsonToken t;
@@ -968,1533 +577,1894 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
         }
         _nextToken = t;
         return name;
-    }
-
-    private final void _isNextTokenNameYes(int i) throws IOException
+    }// note: identical to one in UTF8StreamJsonParser
+    @Override
+    public final Boolean nextBooleanValue() throws IOException
     {
-        _currToken = JsonToken.FIELD_NAME;
-        _updateLocation();
-
-        switch (i) {
-        case '"':
-            _tokenIncomplete = true;
-            _nextToken = JsonToken.VALUE_STRING;
-            return;
-        case '[':
-            _nextToken = JsonToken.START_ARRAY;
-            return;
-        case '{':
-            _nextToken = JsonToken.START_OBJECT;
-            return;
-        case 't':
-            _matchToken("true", 1);
-            _nextToken = JsonToken.VALUE_TRUE;
-            return;
-        case 'f':
-            _matchToken("false", 1);
-            _nextToken = JsonToken.VALUE_FALSE;
-            return;
-        case 'n':
-            _matchToken("null", 1);
-            _nextToken = JsonToken.VALUE_NULL;
-            return;
-        case '-':
-            _nextToken = _parseNegNumber();
-            return;
-        case '0':
-        case '1':
-        case '2':
-        case '3':
-        case '4':
-        case '5':
-        case '6':
-        case '7':
-        case '8':
-        case '9':
-            _nextToken = _parsePosNumber(i);
-            return;
+        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
+            _nameCopied = false;
+            JsonToken t = _nextToken;
+            _nextToken = null;
+            _currToken = t;
+            if (t == JsonToken.VALUE_TRUE) {
+                return Boolean.TRUE;
+            }
+            if (t == JsonToken.VALUE_FALSE) {
+                return Boolean.FALSE;
+            }
+            if (t == JsonToken.START_ARRAY) {
+                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            } else if (t == JsonToken.START_OBJECT) {
+                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            }
+            return null;
         }
-        _nextToken = _handleOddValue(i);
-    }
-
-    protected boolean _isNextTokenNameMaybe(int i, String nameToMatch) throws IOException
+        JsonToken t = nextToken();
+        if (t != null) {
+            int id = t.id();
+            if (id == ID_TRUE) return Boolean.TRUE;
+            if (id == ID_FALSE) return Boolean.FALSE;
+        }
+        return null;
+    }// @since 2.1
+    @Override
+    public final String getValueAsString() throws IOException
     {
-        // // // and this is back to standard nextToken()
-        String name = (i == INT_QUOTE) ? _parseName() : _handleOddName(i);
-        _parsingContext.setCurrentName(name);
-        _currToken = JsonToken.FIELD_NAME;
-        i = _skipColon();
-        _updateLocation();
-        if (i == INT_QUOTE) {
-            _tokenIncomplete = true;
-            _nextToken = JsonToken.VALUE_STRING;
-            return nameToMatch.equals(name);
+        if (_currToken == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                _finishString(); // only strings can be incomplete
+            }
+            return _textBuffer.contentsAsString();
         }
-        // Ok: we must have a value... what is it?
-        JsonToken t;
-        switch (i) {
-        case '-':
-            t = _parseNegNumber();
-            break;
-        case '0':
-        case '1':
-        case '2':
-        case '3':
-        case '4':
-        case '5':
-        case '6':
-        case '7':
-        case '8':
-        case '9':
-            t = _parsePosNumber(i);
-            break;
-        case 'f':
-            _matchFalse();
-            t = JsonToken.VALUE_FALSE;
-            break;
-        case 'n':
-            _matchNull();
-            t = JsonToken.VALUE_NULL;
-            break;
-        case 't':
-            _matchTrue();
-            t = JsonToken.VALUE_TRUE;
-            break;
-        case '[':
-            t = JsonToken.START_ARRAY;
-            break;
-        case '{':
-            t = JsonToken.START_OBJECT;
-            break;
-        default:
-            t = _handleOddValue(i);
-            break;
+        if (_currToken == JsonToken.FIELD_NAME) {
+            return getCurrentName();
         }
-        _nextToken = t;
-        return nameToMatch.equals(name);
-    }
-
-    private final JsonToken _nextTokenNotInObject(int i) throws IOException
-    {
-        if (i == INT_QUOTE) {
-            _tokenIncomplete = true;
-            return (_currToken = JsonToken.VALUE_STRING);
+        return super.getValueAsString(null);
+    }// @since 2.1
+    @Override
+    public final String getValueAsString(String defValue) throws IOException {
+        if (_currToken == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                _finishString(); // only strings can be incomplete
+            }
+            return _textBuffer.contentsAsString();
         }
-        switch (i) {
-        case '[':
-            _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
-            return (_currToken = JsonToken.START_ARRAY);
-        case '{':
-            _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
-            return (_currToken = JsonToken.START_OBJECT);
-        case 't':
-            _matchToken("true", 1);
-            return (_currToken = JsonToken.VALUE_TRUE);
-        case 'f':
-            _matchToken("false", 1);
-            return (_currToken = JsonToken.VALUE_FALSE);
-        case 'n':
-            _matchToken("null", 1);
-            return (_currToken = JsonToken.VALUE_NULL);
-        case '-':
-            return (_currToken = _parseNegNumber());
-            /* Should we have separate handling for plus? Although
-             * it is not allowed per se, it may be erroneously used,
-             * and could be indicated by a more specific error message.
-             */
-        case '0':
-        case '1':
-        case '2':
-        case '3':
-        case '4':
-        case '5':
-        case '6':
-        case '7':
-        case '8':
-        case '9':
-            return (_currToken = _parsePosNumber(i));
-        /*
-         * This check proceeds only if the Feature.ALLOW_MISSING_VALUES is enabled
-         * The Check is for missing values. Incase of missing values in an array, the next token will be either ',' or ']'.
-         * This case, decrements the already incremented _inputPtr in the buffer in case of comma(,) 
-         * so that the existing flow goes back to checking the next token which will be comma again and
-         * it continues the parsing.
-         * Also the case returns NULL as current token in case of ',' or ']'.    
-         */
-        case ',':
-        case ']':
-        	if(isEnabled(Feature.ALLOW_MISSING_VALUES)) {
-        		_inputPtr--;
-        		return (_currToken = JsonToken.VALUE_NULL);  
-        	}    
+        if (_currToken == JsonToken.FIELD_NAME) {
+            return getCurrentName();
         }
-        return (_currToken = _handleOddValue(i));
-    }
-
-    // note: identical to one in UTF8StreamJsonParser
-    @Override
-    public final String nextTextValue() throws IOException
+        return super.getValueAsString(defValue);
+    }@Override
+    public JsonLocation getTokenLocation()
     {
-        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
-            _nameCopied = false;
-            JsonToken t = _nextToken;
-            _nextToken = null;
-            _currToken = t;
-            if (t == JsonToken.VALUE_STRING) {
+        if (_currToken == JsonToken.FIELD_NAME) {
+            long total = _currInputProcessed + (_nameStartOffset-1);
+            return new JsonLocation(_getSourceReference(),
+                    -1L, total, _nameStartRow, _nameStartCol);
+        }
+        return new JsonLocation(_getSourceReference(),
+                -1L, _tokenInputTotal-1, _tokenInputRow, _tokenInputCol);
+    }@Override
+    public final int getTextOffset() throws IOException
+    {
+        // Most have offset of 0, only some may have other values:
+        if (_currToken != null) {
+            switch (_currToken.id()) {
+            case ID_FIELD_NAME:
+                return 0;
+            case ID_STRING:
                 if (_tokenIncomplete) {
                     _tokenIncomplete = false;
-                    _finishString();
+                    _finishString(); // only strings can be incomplete
                 }
-                return _textBuffer.contentsAsString();
-            }
-            if (t == JsonToken.START_ARRAY) {
-                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
-            } else if (t == JsonToken.START_OBJECT) {
-                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+                // fall through
+            case ID_NUMBER_INT:
+            case ID_NUMBER_FLOAT:
+                return _textBuffer.getTextOffset();
+            default:
             }
-            return null;
         }
-        // !!! TODO: optimize this case as well
-        return (nextToken() == JsonToken.VALUE_STRING) ? getText() : null;
-    }
-
-    // note: identical to one in Utf8StreamParser
-    @Override
-    public final int nextIntValue(int defaultValue) throws IOException
+        return 0;
+    }@Override
+    public final int getTextLength() throws IOException
     {
-        if (_currToken == JsonToken.FIELD_NAME) {
-            _nameCopied = false;
-            JsonToken t = _nextToken;
-            _nextToken = null;
-            _currToken = t;
-            if (t == JsonToken.VALUE_NUMBER_INT) {
-                return getIntValue();
-            }
-            if (t == JsonToken.START_ARRAY) {
-                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
-            } else if (t == JsonToken.START_OBJECT) {
-                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+        if (_currToken != null) { // null only before/after document
+            switch (_currToken.id()) {
+            case ID_FIELD_NAME:
+                return _parsingContext.getCurrentName().length();
+            case ID_STRING:
+                if (_tokenIncomplete) {
+                    _tokenIncomplete = false;
+                    _finishString(); // only strings can be incomplete
+                }
+                // fall through
+            case ID_NUMBER_INT:
+            case ID_NUMBER_FLOAT:
+                return _textBuffer.size();
+            default:
+                return _currToken.asCharArray().length;
             }
-            return defaultValue;
         }
-        // !!! TODO: optimize this case as well
-        return (nextToken() == JsonToken.VALUE_NUMBER_INT) ? getIntValue() : defaultValue;
-    }
-
-    // note: identical to one in Utf8StreamParser
-    @Override
-    public final long nextLongValue(long defaultValue) throws IOException
+        return 0;
+    }@Override
+    public final char[] getTextCharacters() throws IOException
     {
-        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
-            _nameCopied = false;
-            JsonToken t = _nextToken;
-            _nextToken = null;
-            _currToken = t;
-            if (t == JsonToken.VALUE_NUMBER_INT) {
-                return getLongValue();
-            }
-            if (t == JsonToken.START_ARRAY) {
-                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
-            } else if (t == JsonToken.START_OBJECT) {
-                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+        if (_currToken != null) { // null only before/after document
+            switch (_currToken.id()) {
+            case ID_FIELD_NAME:
+                if (!_nameCopied) {
+                    String name = _parsingContext.getCurrentName();
+                    int nameLen = name.length();
+                    if (_nameCopyBuffer == null) {
+                        _nameCopyBuffer = _ioContext.allocNameCopyBuffer(nameLen);
+                    } else if (_nameCopyBuffer.length < nameLen) {
+                        _nameCopyBuffer = new char[nameLen];
+                    }
+                    name.getChars(0, nameLen, _nameCopyBuffer, 0);
+                    _nameCopied = true;
+                }
+                return _nameCopyBuffer;
+            case ID_STRING:
+                if (_tokenIncomplete) {
+                    _tokenIncomplete = false;
+                    _finishString(); // only strings can be incomplete
+                }
+                // fall through
+            case ID_NUMBER_INT:
+            case ID_NUMBER_FLOAT:
+                return _textBuffer.getTextBuffer();
+            default:
+                return _currToken.asCharArray();
             }
-            return defaultValue;
         }
-        // !!! TODO: optimize this case as well
-        return (nextToken() == JsonToken.VALUE_NUMBER_INT) ? getLongValue() : defaultValue;
-    }
-
-    // note: identical to one in UTF8StreamJsonParser
+        return null;
+    } /**
+     * Method for accessing textual representation of the current event;
+     * if no current event (before first call to {@link #nextToken}, or
+     * after encountering end-of-input), returns null.
+     * Method can be called for any event.
+     */
     @Override
-    public final Boolean nextBooleanValue() throws IOException
+    public final String getText() throws IOException
     {
-        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
-            _nameCopied = false;
-            JsonToken t = _nextToken;
-            _nextToken = null;
-            _currToken = t;
-            if (t == JsonToken.VALUE_TRUE) {
-                return Boolean.TRUE;
-            }
-            if (t == JsonToken.VALUE_FALSE) {
-                return Boolean.FALSE;
+        JsonToken t = _currToken;
+        if (t == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                _finishString(); // only strings can be incomplete
             }
-            if (t == JsonToken.START_ARRAY) {
-                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
-            } else if (t == JsonToken.START_OBJECT) {
-                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            return _textBuffer.contentsAsString();
+        }
+        return _getText2(t);
+    }@Override // since 2.8
+    public int getText(Writer writer) throws IOException
+    {
+        JsonToken t = _currToken;
+        if (t == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                _finishString(); // only strings can be incomplete
             }
-            return null;
+            return _textBuffer.contentsToWriter(writer);
+        }
+        if (t == JsonToken.FIELD_NAME) {
+            String n = _parsingContext.getCurrentName();
+            writer.write(n);
+            return n.length();
         }
-        JsonToken t = nextToken();
         if (t != null) {
-            int id = t.id();
-            if (id == ID_TRUE) return Boolean.TRUE;
-            if (id == ID_FALSE) return Boolean.FALSE;
+            if (t.isNumeric()) {
+                return _textBuffer.contentsToWriter(writer);
+            }
+            char[] ch = t.asCharArray();
+            writer.write(ch);
+            return ch.length;
         }
-        return null;
-    }
-
-    /*
-    /**********************************************************
-    /* Internal methods, number parsing
-    /**********************************************************
-     */
-
-    /**
-     * Initial parsing method for number values. It needs to be able
-     * to parse enough input to be able to determine whether the
-     * value is to be considered a simple integer value, or a more
-     * generic decimal value: latter of which needs to be expressed
-     * as a floating point number. The basic rule is that if the number
-     * has no fractional or exponential part, it is an integer; otherwise
-     * a floating point number.
-     *<p>
-     * Because much of input has to be processed in any case, no partial
-     * parsing is done: all input text will be stored for further
-     * processing. However, actual numeric value conversion will be
-     * deferred, since it is usually the most complicated and costliest
-     * part of processing.
-     */
-    protected final JsonToken _parsePosNumber(int ch) throws IOException
+        return 0;
+    }@Deprecated // since 2.8
+    protected char getNextChar(String eofMsg) throws IOException {
+        return getNextChar(eofMsg, null);
+    }protected char getNextChar(String eofMsg, JsonToken forToken) throws IOException {
+        if (_inputPtr >= _inputEnd) {
+            if (!_loadMore()) {
+                _reportInvalidEOF(eofMsg, forToken);
+            }
+        }
+        return _inputBuffer[_inputPtr++];
+    }@Override public Object getInputSource() { return _reader; }@Override
+    public JsonLocation getCurrentLocation() {
+        int col = _inputPtr - _currInputRowStart + 1; // 1-based
+        return new JsonLocation(_getSourceReference(),
+                -1L, _currInputProcessed + _inputPtr,
+                _currInputRow, col);
+    }@Override public ObjectCodec getCodec() { return _objectCodec; }@Override
+    public byte[] getBinaryValue(Base64Variant b64variant) throws IOException
     {
-        /* Although we will always be complete with respect to textual
-         * representation (that is, all characters will be parsed),
-         * actual conversion to a number is deferred. Thus, need to
-         * note that no representations are valid yet
-         */
-        int ptr = _inputPtr;
-        int startPtr = ptr-1; // to include digit already read
-        final int inputLen = _inputEnd;
-
-        // One special case, leading zero(es):
-        if (ch == INT_0) {
-            return _parseNumber2(false, startPtr);
+        if ((_currToken == JsonToken.VALUE_EMBEDDED_OBJECT) && (_binaryValue != null)) {
+            return _binaryValue;
         }
-
-        /* First, let's see if the whole number is contained within
-         * the input buffer unsplit. This should be the common case;
-         * and to simplify processing, we will just reparse contents
-         * in the alternative case (number split on buffer boundary)
-         */
-
-        int intLen = 1; // already got one
-
-        // First let's get the obligatory integer part:
-        int_loop:
-        while (true) {
-            if (ptr >= inputLen) {
-                _inputPtr = startPtr;
-                return _parseNumber2(false, startPtr);
+        if (_currToken != JsonToken.VALUE_STRING) {
+            _reportError("Current token ("+_currToken+") not VALUE_STRING or VALUE_EMBEDDED_OBJECT, can not access as binary");
+        }
+        // To ensure that we won't see inconsistent data, better clear up state
+        if (_tokenIncomplete) {
+            try {
+                _binaryValue = _decodeBase64(b64variant);
+            } catch (IllegalArgumentException iae) {
+                throw _constructError("Failed to decode VALUE_STRING as base64 ("+b64variant+"): "+iae.getMessage());
             }
-            ch = (int) _inputBuffer[ptr++];
-            if (ch < INT_0 || ch > INT_9) {
-                break int_loop;
+            /* let's clear incomplete only now; allows for accessing other
+             * textual content in error cases
+             */
+            _tokenIncomplete = false;
+        } else { // may actually require conversion...
+            if (_binaryValue == null) {
+                @SuppressWarnings("resource")
+                ByteArrayBuilder builder = _getByteArrayBuilder();
+                _decodeBase64(getText(), builder, b64variant);
+                _binaryValue = builder.toByteArray();
             }
-            ++intLen;
         }
-        if (ch == INT_PERIOD || ch == INT_e || ch == INT_E) {
-            _inputPtr = ptr;
-            return _parseFloat(ch, startPtr, ptr, false, intLen);
+        return _binaryValue;
+    }@Override
+    public void finishToken() throws IOException {
+        if (_tokenIncomplete) {
+            _tokenIncomplete = false;
+            _finishString(); // only strings can be incomplete
         }
-        // Got it all: let's add to text buffer for parsing, access
-        --ptr; // need to push back following separator
-        _inputPtr = ptr;
-        // As per #105, need separating space between root values; check here
-        if (_parsingContext.inRoot()) {
-            _verifyRootSpace(ch);
+    } /**
+     * Method called to ensure that a root-value is followed by a space
+     * token.
+     *<p>
+     * NOTE: caller MUST ensure there is at least one character available;
+     * and that input pointer is AT given char (not past)
+     */
+    private final void _verifyRootSpace(int ch) throws IOException
+    {
+        // caller had pushed it back, before calling; reset
+        ++_inputPtr;
+        switch (ch) {
+        case ' ':
+        case '\t':
+            return;
+        case '\r':
+            _skipCR();
+            return;
+        case '\n':
+            ++_currInputRow;
+            _currInputRowStart = _inputPtr;
+            return;
         }
-        int len = ptr-startPtr;
-        _textBuffer.resetWithShared(_inputBuffer, startPtr, len);
-        return resetInt(false, intLen);
-    }
-
-    private final JsonToken _parseFloat(int ch, int startPtr, int ptr, boolean neg, int intLen)
-        throws IOException
+        _reportMissingRootWS(ch);
+    } /**
+     * Method called when we have seen one zero, and want to ensure
+     * it is not followed by another
+     */
+    private final char _verifyNoLeadingZeroes() throws IOException
     {
-        final int inputLen = _inputEnd;
-        int fractLen = 0;
-
-        // And then see if we get other parts
-        if (ch == '.') { // yes, fraction
-            fract_loop:
-            while (true) {
-                if (ptr >= inputLen) {
-                    return _parseNumber2(neg, startPtr);
-                }
-                ch = (int) _inputBuffer[ptr++];
-                if (ch < INT_0 || ch > INT_9) {
-                    break fract_loop;
-                }
-                ++fractLen;
-            }
-            // must be followed by sequence of ints, one minimum
-            if (fractLen == 0) {
-                reportUnexpectedNumberChar(ch, "Decimal point not followed by a digit");
+        // Fast case first:
+        if (_inputPtr < _inputEnd) {
+            char ch = _inputBuffer[_inputPtr];
+            // if not followed by a number (probably '.'); return zero as is, to be included
+            if (ch < '0' || ch > '9') {
+                return '0';
             }
         }
-        int expLen = 0;
-        if (ch == 'e' || ch == 'E') { // and/or exponent
-            if (ptr >= inputLen) {
-                _inputPtr = startPtr;
-                return _parseNumber2(neg, startPtr);
-            }
-            // Sign indicator?
-            ch = (int) _inputBuffer[ptr++];
-            if (ch == INT_MINUS || ch == INT_PLUS) { // yup, skip for now
-                if (ptr >= inputLen) {
-                    _inputPtr = startPtr;
-                    return _parseNumber2(neg, startPtr);
+        // and offline the less common case
+        return _verifyNLZ2();
+    }private char _verifyNLZ2() throws IOException
+    {
+        if (_inputPtr >= _inputEnd && !_loadMore()) {
+            return '0';
+        }
+        char ch = _inputBuffer[_inputPtr];
+        if (ch < '0' || ch > '9') {
+            return '0';
+        }
+        if (!isEnabled(Feature.ALLOW_NUMERIC_LEADING_ZEROS)) {
+            reportInvalidNumber("Leading zeroes not allowed");
+        }
+        // if so, just need to skip either all zeroes (if followed by number); or all but one (if non-number)
+        ++_inputPtr; // Leading zero to be skipped
+        if (ch == INT_0) {
+            while (_inputPtr < _inputEnd || _loadMore()) {
+                ch = _inputBuffer[_inputPtr];
+                if (ch < '0' || ch > '9') { // followed by non-number; retain one zero
+                    return '0';
                 }
-                ch = (int) _inputBuffer[ptr++];
-            }
-            while (ch <= INT_9 && ch >= INT_0) {
-                ++expLen;
-                if (ptr >= inputLen) {
-                    _inputPtr = startPtr;
-                    return _parseNumber2(neg, startPtr);
+                ++_inputPtr; // skip previous zero
+                if (ch != '0') { // followed by other number; return
+                    break;
                 }
-                ch = (int) _inputBuffer[ptr++];
-            }
-            // must be followed by sequence of ints, one minimum
-            if (expLen == 0) {
-                reportUnexpectedNumberChar(ch, "Exponent indicator not followed by a digit");
             }
         }
-        --ptr; // need to push back following separator
-        _inputPtr = ptr;
-        // As per #105, need separating space between root values; check here
-        if (_parsingContext.inRoot()) {
-            _verifyRootSpace(ch);
-        }
-        int len = ptr-startPtr;
-        _textBuffer.resetWithShared(_inputBuffer, startPtr, len);
-        // And there we have it!
-        return resetFloat(neg, intLen, fractLen, expLen);
-    }
-
-    protected final JsonToken _parseNegNumber() throws IOException
+        return ch;
+    }// @since 2.7
+    private final void _updateNameLocation()
     {
         int ptr = _inputPtr;
-        int startPtr = ptr-1; // to include sign/digit already read
-        final int inputLen = _inputEnd;
-
-        if (ptr >= inputLen) {
-            return _parseNumber2(true, startPtr);
-        }
-        int ch = _inputBuffer[ptr++];
-        // First check: must have a digit to follow minus sign
-        if (ch > INT_9 || ch < INT_0) {
-            _inputPtr = ptr;
-            return _handleInvalidNumberStart(ch, true);
-        }
-        // One special case, leading zero(es):
-        if (ch == INT_0) {
-            return _parseNumber2(true, startPtr);
+        _nameStartOffset = ptr;
+        _nameStartRow = _currInputRow;
+        _nameStartCol = ptr - _currInputRowStart;
+    }// @since 2.7
+    private final void _updateLocation()
+    {
+        int ptr = _inputPtr;
+        _tokenInputTotal = _currInputProcessed + ptr;
+        _tokenInputRow = _currInputRow;
+        _tokenInputCol = ptr - _currInputRowStart;
+    }private boolean _skipYAMLComment() throws IOException
+    {
+        if (!isEnabled(Feature.ALLOW_YAML_COMMENTS)) {
+            return false;
         }
-        int intLen = 1; // already got one
-
-        // First let's get the obligatory integer part:
-        int_loop:
+        _skipLine();
+        return true;
+    }private int _skipWSOrEnd2() throws IOException
+    {
         while (true) {
-            if (ptr >= inputLen) {
-                return _parseNumber2(true, startPtr);
-            }
-            ch = (int) _inputBuffer[ptr++];
-            if (ch < INT_0 || ch > INT_9) {
-                break int_loop;
+            if (_inputPtr >= _inputEnd) {
+                if (!_loadMore()) { // We ran out of input...
+                    return _eofAsNextChar();
+                }
             }
-            ++intLen;
-        }
-
-        if (ch == INT_PERIOD || ch == INT_e || ch == INT_E) {
-            _inputPtr = ptr;
-            return _parseFloat(ch, startPtr, ptr, true, intLen);
-        }
-        --ptr;
-        _inputPtr = ptr;
-        if (_parsingContext.inRoot()) {
-            _verifyRootSpace(ch);
-        }
-        int len = ptr-startPtr;
-        _textBuffer.resetWithShared(_inputBuffer, startPtr, len);
-        return resetInt(true, intLen);
-    }
-
-    /**
-     * Method called to parse a number, when the primary parse
-     * method has failed to parse it, due to it being split on
-     * buffer boundary. As a result code is very similar, except
-     * that it has to explicitly copy contents to the text buffer
-     * instead of just sharing the main input buffer.
-     */
-    private final JsonToken _parseNumber2(boolean neg, int startPtr) throws IOException
-    {
-        _inputPtr = neg ? (startPtr+1) : startPtr;
-        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
-        int outPtr = 0;
-
-        // Need to prepend sign?
-        if (neg) {
-            outBuf[outPtr++] = '-';
-        }
-
-        // This is the place to do leading-zero check(s) too:
-        int intLen = 0;
-        char c = (_inputPtr < _inputEnd) ? _inputBuffer[_inputPtr++]
-                : getNextChar("No digit following minus sign", JsonToken.VALUE_NUMBER_INT);
-        if (c == '0') {
-            c = _verifyNoLeadingZeroes();
-        }
-        boolean eof = false;
-
-        // Ok, first the obligatory integer part:
-        int_loop:
-        while (c >= '0' && c <= '9') {
-            ++intLen;
-            if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
-                outPtr = 0;
-            }
-            outBuf[outPtr++] = c;
-            if (_inputPtr >= _inputEnd && !_loadMore()) {
-                // EOF is legal for main level int values
-                c = CHAR_NULL;
-                eof = true;
-                break int_loop;
-            }
-            c = _inputBuffer[_inputPtr++];
-        }
-        // Also, integer part is not optional
-        if (intLen == 0) {
-            return _handleInvalidNumberStart(c, neg);
-        }
-
-        int fractLen = 0;
-        // And then see if we get other parts
-        if (c == '.') { // yes, fraction
-            if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
-                outPtr = 0;
-            }
-            outBuf[outPtr++] = c;
-
-            fract_loop:
-            while (true) {
-                if (_inputPtr >= _inputEnd && !_loadMore()) {
-                    eof = true;
-                    break fract_loop;
+            int i = (int) _inputBuffer[_inputPtr++];
+            if (i > INT_SPACE) {
+                if (i == INT_SLASH) {
+                    _skipComment();
+                    continue;
                 }
-                c = _inputBuffer[_inputPtr++];
-                if (c < INT_0 || c > INT_9) {
-                    break fract_loop;
+                if (i == INT_HASH) {
+                    if (_skipYAMLComment()) {
+                        continue;
+                    }
                 }
-                ++fractLen;
-                if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
-                    outPtr = 0;
+                return i;
+            } else if (i != INT_SPACE) {
+                if (i == INT_LF) {
+                    ++_currInputRow;
+                    _currInputRowStart = _inputPtr;
+                } else if (i == INT_CR) {
+                    _skipCR();
+                } else if (i != INT_TAB) {
+                    _throwInvalidSpace(i);
                 }
-                outBuf[outPtr++] = c;
-            }
-            // must be followed by sequence of ints, one minimum
-            if (fractLen == 0) {
-                reportUnexpectedNumberChar(c, "Decimal point not followed by a digit");
             }
         }
-
-        int expLen = 0;
-        if (c == 'e' || c == 'E') { // exponent?
-            if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
-                outPtr = 0;
-            }
-            outBuf[outPtr++] = c;
-            // Not optional, can require that we get one more char
-            c = (_inputPtr < _inputEnd) ? _inputBuffer[_inputPtr++]
-                : getNextChar("expected a digit for number exponent");
-            // Sign indicator?
-            if (c == '-' || c == '+') {
-                if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
-                    outPtr = 0;
-                }
-                outBuf[outPtr++] = c;
-                // Likewise, non optional:
-                c = (_inputPtr < _inputEnd) ? _inputBuffer[_inputPtr++]
-                    : getNextChar("expected a digit for number exponent");
-            }
-
-            exp_loop:
-            while (c <= INT_9 && c >= INT_0) {
-                ++expLen;
-                if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
-                    outPtr = 0;
-                }
-                outBuf[outPtr++] = c;
-                if (_inputPtr >= _inputEnd && !_loadMore()) {
-                    eof = true;
-                    break exp_loop;
-                }
-                c = _inputBuffer[_inputPtr++];
-            }
-            // must be followed by sequence of ints, one minimum
-            if (expLen == 0) {
-                reportUnexpectedNumberChar(c, "Exponent indicator not followed by a digit");
+    }private final int _skipWSOrEnd() throws IOException
+    {
+        // Let's handle first character separately since it is likely that
+        // it is either non-whitespace; or we have longer run of white space
+        if (_inputPtr >= _inputEnd) {
+            if (!_loadMore()) {
+                return _eofAsNextChar();
             }
         }
-
-        // Ok; unless we hit end-of-input, need to push last char read back
-        if (!eof) {
-            --_inputPtr;
-            if (_parsingContext.inRoot()) {
-                _verifyRootSpace(c);
+        int i = _inputBuffer[_inputPtr++];
+        if (i > INT_SPACE) {
+            if (i == INT_SLASH || i == INT_HASH) {
+                --_inputPtr;
+                return _skipWSOrEnd2();
             }
+            return i;
         }
-        _textBuffer.setCurrentLength(outPtr);
-        // And there we have it!
-        return reset(neg, intLen, fractLen, expLen);
-    }
-
-    /**
-     * Method called when we have seen one zero, and want to ensure
-     * it is not followed by another
-     */
-    private final char _verifyNoLeadingZeroes() throws IOException
-    {
-        // Fast case first:
-        if (_inputPtr < _inputEnd) {
-            char ch = _inputBuffer[_inputPtr];
-            // if not followed by a number (probably '.'); return zero as is, to be included
-            if (ch < '0' || ch > '9') {
-                return '0';
+        if (i != INT_SPACE) {
+            if (i == INT_LF) {
+                ++_currInputRow;
+                _currInputRowStart = _inputPtr;
+            } else if (i == INT_CR) {
+                _skipCR();
+            } else if (i != INT_TAB) {
+                _throwInvalidSpace(i);
             }
         }
-        // and offline the less common case
-        return _verifyNLZ2();
-    }
 
-    private char _verifyNLZ2() throws IOException
-    {
-        if (_inputPtr >= _inputEnd && !_loadMore()) {
-            return '0';
-        }
-        char ch = _inputBuffer[_inputPtr];
-        if (ch < '0' || ch > '9') {
-            return '0';
-        }
-        if (!isEnabled(Feature.ALLOW_NUMERIC_LEADING_ZEROS)) {
-            reportInvalidNumber("Leading zeroes not allowed");
-        }
-        // if so, just need to skip either all zeroes (if followed by number); or all but one (if non-number)
-        ++_inputPtr; // Leading zero to be skipped
-        if (ch == INT_0) {
-            while (_inputPtr < _inputEnd || _loadMore()) {
-                ch = _inputBuffer[_inputPtr];
-                if (ch < '0' || ch > '9') { // followed by non-number; retain one zero
-                    return '0';
+        while (_inputPtr < _inputEnd) {
+            i = (int) _inputBuffer[_inputPtr++];
+            if (i > INT_SPACE) {
+                if (i == INT_SLASH || i == INT_HASH) {
+                    --_inputPtr;
+                    return _skipWSOrEnd2();
                 }
-                ++_inputPtr; // skip previous zero
-                if (ch != '0') { // followed by other number; return
-                    break;
+                return i;
+            }
+            if (i != INT_SPACE) {
+                if (i == INT_LF) {
+                    ++_currInputRow;
+                    _currInputRowStart = _inputPtr;
+                } else if (i == INT_CR) {
+                    _skipCR();
+                } else if (i != INT_TAB) {
+                    _throwInvalidSpace(i);
                 }
             }
         }
-        return ch;
-    }
-
-    /**
-     * Method called if expected numeric value (due to leading sign) does not
-     * look like a number
+        return _skipWSOrEnd2();
+    } /**
+     * Method called to skim through rest of unparsed String value,
+     * if it is not needed. This can be done bit faster if contents
+     * need not be stored for future access.
      */
-    protected JsonToken _handleInvalidNumberStart(int ch, boolean negative) throws IOException
+    protected final void _skipString() throws IOException
     {
-        if (ch == 'I') {
-            if (_inputPtr >= _inputEnd) {
+        _tokenIncomplete = false;
+
+        int inPtr = _inputPtr;
+        int inLen = _inputEnd;
+        char[] inBuf = _inputBuffer;
+
+        while (true) {
+            if (inPtr >= inLen) {
+                _inputPtr = inPtr;
                 if (!_loadMore()) {
-                    _reportInvalidEOFInValue(JsonToken.VALUE_NUMBER_INT);
-                }
-            }
-            ch = _inputBuffer[_inputPtr++];
-            if (ch == 'N') {
-                String match = negative ? "-INF" :"+INF";
-                _matchToken(match, 3);
-                if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
-                    return resetAsNaN(match, negative ? Double.NEGATIVE_INFINITY : Double.POSITIVE_INFINITY);
-                }
-                _reportError("Non-standard token '"+match+"': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
-            } else if (ch == 'n') {
-                String match = negative ? "-Infinity" :"+Infinity";
-                _matchToken(match, 3);
-                if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
-                    return resetAsNaN(match, negative ? Double.NEGATIVE_INFINITY : Double.POSITIVE_INFINITY);
-                }
-                _reportError("Non-standard token '"+match+"': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
-            }
-        }
-        reportUnexpectedNumberChar(ch, "expected digit (0-9) to follow minus sign, for valid numeric value");
-        return null;
-    }
-
-    /**
-     * Method called to ensure that a root-value is followed by a space
-     * token.
-     *<p>
-     * NOTE: caller MUST ensure there is at least one character available;
-     * and that input pointer is AT given char (not past)
-     */
-    private final void _verifyRootSpace(int ch) throws IOException
-    {
-        // caller had pushed it back, before calling; reset
-        ++_inputPtr;
-        switch (ch) {
-        case ' ':
-        case '\t':
-            return;
-        case '\r':
-            _skipCR();
-            return;
-        case '\n':
-            ++_currInputRow;
-            _currInputRowStart = _inputPtr;
-            return;
-        }
-        _reportMissingRootWS(ch);
-    }
-
-    /*
-    /**********************************************************
-    /* Internal methods, secondary parsing
-    /**********************************************************
-     */
-
-    protected final String _parseName() throws IOException
-    {
-        // First: let's try to see if we have a simple name: one that does
-        // not cross input buffer boundary, and does not contain escape sequences.
-        int ptr = _inputPtr;
-        int hash = _hashSeed;
-        final int[] codes = _icLatin1;
-
-        while (ptr < _inputEnd) {
-            int ch = _inputBuffer[ptr];
-            if (ch < codes.length && codes[ch] != 0) {
-                if (ch == '"') {
-                    int start = _inputPtr;
-                    _inputPtr = ptr+1; // to skip the quote
-                    return _symbols.findSymbol(_inputBuffer, start, ptr - start, hash);
-                }
-                break;
-            }
-            hash = (hash * CharsToNameCanonicalizer.HASH_MULT) + ch;
-            ++ptr;
-        }
-        int start = _inputPtr;
-        _inputPtr = ptr;
-        return _parseName2(start, hash, INT_QUOTE);
-    }
-
-    private String _parseName2(int startPtr, int hash, int endChar) throws IOException
-    {
-        _textBuffer.resetWithShared(_inputBuffer, startPtr, (_inputPtr - startPtr));
-
-        /* Output pointers; calls will also ensure that the buffer is
-         * not shared and has room for at least one more char.
-         */
-        char[] outBuf = _textBuffer.getCurrentSegment();
-        int outPtr = _textBuffer.getCurrentSegmentSize();
-
-        while (true) {
-            if (_inputPtr >= _inputEnd) {
-                if (!_loadMore()) {
-                    _reportInvalidEOF(" in field name", JsonToken.FIELD_NAME);
+                    _reportInvalidEOF(": was expecting closing quote for a string value",
+                            JsonToken.VALUE_STRING);
                 }
+                inPtr = _inputPtr;
+                inLen = _inputEnd;
             }
-            char c = _inputBuffer[_inputPtr++];
+            char c = inBuf[inPtr++];
             int i = (int) c;
             if (i <= INT_BACKSLASH) {
                 if (i == INT_BACKSLASH) {
-                    /* Although chars outside of BMP are to be escaped as
-                     * an UTF-16 surrogate pair, does that affect decoding?
-                     * For now let's assume it does not.
-                     */
-                    c = _decodeEscaped();
-                } else if (i <= endChar) {
-                    if (i == endChar) {
+                    // Although chars outside of BMP are to be escaped as an UTF-16 surrogate pair,
+                    // does that affect decoding? For now let's assume it does not.
+                    _inputPtr = inPtr;
+                    /*c = */ _decodeEscaped();
+                    inPtr = _inputPtr;
+                    inLen = _inputEnd;
+                } else if (i <= INT_QUOTE) {
+                    if (i == INT_QUOTE) {
+                        _inputPtr = inPtr;
                         break;
                     }
                     if (i < INT_SPACE) {
-                        _throwUnquotedSpace(i, "name");
+                        _inputPtr = inPtr;
+                        _throwUnquotedSpace(i, "string value");
                     }
                 }
             }
-            hash = (hash * CharsToNameCanonicalizer.HASH_MULT) + c;
-            // Ok, let's add char to output:
-            outBuf[outPtr++] = c;
-
-            // Need more room?
-            if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
-                outPtr = 0;
-            }
         }
-        _textBuffer.setCurrentLength(outPtr);
-        {
-            TextBuffer tb = _textBuffer;
-            char[] buf = tb.getTextBuffer();
-            int start = tb.getTextOffset();
-            int len = tb.size();
-            return _symbols.findSymbol(buf, start, len, hash);
+    }private void _skipLine() throws IOException
+    {
+        // Ok: need to find EOF or linefeed
+        while ((_inputPtr < _inputEnd) || _loadMore()) {
+            int i = (int) _inputBuffer[_inputPtr++];
+            if (i < INT_SPACE) {
+                if (i == INT_LF) {
+                    ++_currInputRow;
+                    _currInputRowStart = _inputPtr;
+                    break;
+                } else if (i == INT_CR) {
+                    _skipCR();
+                    break;
+                } else if (i != INT_TAB) {
+                    _throwInvalidSpace(i);
+                }
+            }
         }
-    }
-
-    /**
-     * Method called when we see non-white space character other
-     * than double quote, when expecting a field name.
-     * In standard mode will just throw an expection; but
-     * in non-standard modes may be able to parse name.
-     */
-    protected String _handleOddName(int i) throws IOException
+    }private void _skipComment() throws IOException
     {
-        // [JACKSON-173]: allow single quotes
-        if (i == '\'' && isEnabled(Feature.ALLOW_SINGLE_QUOTES)) {
-            return _parseAposName();
+        if (!isEnabled(Feature.ALLOW_COMMENTS)) {
+            _reportUnexpectedChar('/', "maybe a (non-standard) comment? (not recognized as one since Feature 'ALLOW_COMMENTS' not enabled for parser)");
         }
-        // [JACKSON-69]: allow unquoted names if feature enabled:
-        if (!isEnabled(Feature.ALLOW_UNQUOTED_FIELD_NAMES)) {
-            _reportUnexpectedChar(i, "was expecting double-quote to start field name");
+        // First: check which comment (if either) it is:
+        if (_inputPtr >= _inputEnd && !_loadMore()) {
+            _reportInvalidEOF(" in a comment", null);
         }
-        final int[] codes = CharTypes.getInputCodeLatin1JsNames();
-        final int maxCode = codes.length;
-
-        // Also: first char must be a valid name char, but NOT be number
-        boolean firstOk;
-
-        if (i < maxCode) { // identifier, or a number ([Issue#102])
-            firstOk = (codes[i] == 0);
+        char c = _inputBuffer[_inputPtr++];
+        if (c == '/') {
+            _skipLine();
+        } else if (c == '*') {
+            _skipCComment();
         } else {
-            firstOk = Character.isJavaIdentifierPart((char) i);
+            _reportUnexpectedChar(c, "was expecting either '*' or '/' for a comment");
         }
-        if (!firstOk) {
-            _reportUnexpectedChar(i, "was expecting either valid name character (for unquoted name) or double-quote (for quoted) to start field name");
+    }// Primary loop: no reloading, comment handling
+    private final int _skipComma(int i) throws IOException
+    {
+        if (i != INT_COMMA) {
+            _reportUnexpectedChar(i, "was expecting comma to separate "+_parsingContext.typeDesc()+" entries");
         }
-        int ptr = _inputPtr;
-        int hash = _hashSeed;
-        final int inputLen = _inputEnd;
-
-        if (ptr < inputLen) {
-            do {
-                int ch = _inputBuffer[ptr];
-                if (ch < maxCode) {
-                    if (codes[ch] != 0) {
-                        int start = _inputPtr-1; // -1 to bring back first char
-                        _inputPtr = ptr;
-                        return _symbols.findSymbol(_inputBuffer, start, ptr - start, hash);
-                    }
-                } else if (!Character.isJavaIdentifierPart((char) ch)) {
-                    int start = _inputPtr-1; // -1 to bring back first char
-                    _inputPtr = ptr;
-                    return _symbols.findSymbol(_inputBuffer, start, ptr - start, hash);
+        while (_inputPtr < _inputEnd) {
+            i = (int) _inputBuffer[_inputPtr++];
+            if (i > INT_SPACE) {
+                if (i == INT_SLASH || i == INT_HASH) {
+                    --_inputPtr;
+                    return _skipAfterComma2();
                 }
-                hash = (hash * CharsToNameCanonicalizer.HASH_MULT) + ch;
-                ++ptr;
-            } while (ptr < inputLen);
+                return i;
+            }
+            if (i < INT_SPACE) {
+                if (i == INT_LF) {
+                    ++_currInputRow;
+                    _currInputRowStart = _inputPtr;
+                } else if (i == INT_CR) {
+                    _skipCR();
+                } else if (i != INT_TAB) {
+                    _throwInvalidSpace(i);
+                }
+            }
         }
-        int start = _inputPtr-1;
-        _inputPtr = ptr;
-        return _handleOddName2(start, hash, codes);
-    }
-
-    protected String _parseAposName() throws IOException
+        return _skipAfterComma2();
+    }// Variant called when we know there's at least 4 more bytes available
+    private final int _skipColonFast(int ptr) throws IOException
     {
-        // Note: mostly copy of_parseFieldName
-        int ptr = _inputPtr;
-        int hash = _hashSeed;
-        final int inputLen = _inputEnd;
-
-        if (ptr < inputLen) {
-            final int[] codes = _icLatin1;
-            final int maxCode = codes.length;
-
-            do {
-                int ch = _inputBuffer[ptr];
-                if (ch == '\'') {
-                    int start = _inputPtr;
-                    _inputPtr = ptr+1; // to skip the quote
-                    return _symbols.findSymbol(_inputBuffer, start, ptr - start, hash);
-                }
-                if (ch < maxCode && codes[ch] != 0) {
-                    break;
+        int i = (int) _inputBuffer[ptr++];
+        if (i == INT_COLON) { // common case, no leading space
+            i = _inputBuffer[ptr++];
+            if (i > INT_SPACE) { // nor trailing
+                if (i != INT_SLASH && i != INT_HASH) {
+                    _inputPtr = ptr;
+                    return i;
                 }
-                hash = (hash * CharsToNameCanonicalizer.HASH_MULT) + ch;
-                ++ptr;
-            } while (ptr < inputLen);
+            } else if (i == INT_SPACE || i == INT_TAB) {
+                i = (int) _inputBuffer[ptr++];
+                if (i > INT_SPACE) {
+                    if (i != INT_SLASH && i != INT_HASH) {
+                        _inputPtr = ptr;
+                        return i;
+                    }
+                }
+            }
+            _inputPtr = ptr-1;
+            return _skipColon2(true); // true -> skipped colon
         }
-
-        int start = _inputPtr;
-        _inputPtr = ptr;
-
-        return _parseName2(start, hash, '\'');
-    }
-
-    /**
-     * Method for handling cases where first non-space character
-     * of an expected value token is not legal for standard JSON content.
-     */
-    protected JsonToken _handleOddValue(int i) throws IOException
+        if (i == INT_SPACE || i == INT_TAB) {
+            i = _inputBuffer[ptr++];
+        }
+        boolean gotColon = (i == INT_COLON);
+        if (gotColon) {
+            i = _inputBuffer[ptr++];
+            if (i > INT_SPACE) {
+                if (i != INT_SLASH && i != INT_HASH) {
+                    _inputPtr = ptr;
+                    return i;
+                }
+            } else if (i == INT_SPACE || i == INT_TAB) {
+                i = (int) _inputBuffer[ptr++];
+                if (i > INT_SPACE) {
+                    if (i != INT_SLASH && i != INT_HASH) {
+                        _inputPtr = ptr;
+                        return i;
+                    }
+                }
+            }
+        }
+        _inputPtr = ptr-1;
+        return _skipColon2(gotColon);
+    }private final int _skipColon2(boolean gotColon) throws IOException
     {
-        // Most likely an error, unless we are to allow single-quote-strings
-        switch (i) {
-        case '\'':
-            /* Allow single quotes? Unlike with regular Strings, we'll eagerly parse
-             * contents; this so that there'sno need to store information on quote char used.
-             * Also, no separation to fast/slow parsing; we'll just do
-             * one regular (~= slowish) parsing, to keep code simple
-             */
-            if (isEnabled(Feature.ALLOW_SINGLE_QUOTES)) {
-                return _handleApos();
+        while (_inputPtr < _inputEnd || _loadMore()) {
+            int i = (int) _inputBuffer[_inputPtr++];
+            if (i > INT_SPACE) {
+                if (i == INT_SLASH) {
+                    _skipComment();
+                    continue;
+                }
+                if (i == INT_HASH) {
+                    if (_skipYAMLComment()) {
+                        continue;
+                    }
+                }
+                if (gotColon) {
+                    return i;
+                }
+                if (i != INT_COLON) {
+                    _reportUnexpectedChar(i, "was expecting a colon to separate field name and value");
+                }
+                gotColon = true;
+                continue;
             }
-            break;
-        case ']':
-            /* 28-Mar-2016: [core#116]: If Feature.ALLOW_MISSING_VALUES is enabled
-             *   we may allow "missing values", that is, encountering a trailing
-             *   comma or closing marker where value would be expected
-             */
-            if (!_parsingContext.inArray()) {
-                break;
+            if (i < INT_SPACE) {
+                if (i == INT_LF) {
+                    ++_currInputRow;
+                    _currInputRowStart = _inputPtr;
+                } else if (i == INT_CR) {
+                    _skipCR();
+                } else if (i != INT_TAB) {
+                    _throwInvalidSpace(i);
+                }
             }
-            // fall through
-        case ',':
-            if (isEnabled(Feature.ALLOW_MISSING_VALUES)) {
-                --_inputPtr;
-                return JsonToken.VALUE_NULL;
+        }
+        _reportInvalidEOF(" within/between "+_parsingContext.typeDesc()+" entries",
+                null);
+        return -1;
+    }private final int _skipColon() throws IOException
+    {
+        if ((_inputPtr + 4) >= _inputEnd) {
+            return _skipColon2(false);
+        }
+        char c = _inputBuffer[_inputPtr];
+        if (c == ':') { // common case, no leading space
+            int i = _inputBuffer[++_inputPtr];
+            if (i > INT_SPACE) { // nor trailing
+                if (i == INT_SLASH || i == INT_HASH) {
+                    return _skipColon2(true);
+                }
+                ++_inputPtr;
+                return i;
             }
-            break;
-        case 'N':
-            _matchToken("NaN", 1);
-            if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
-                return resetAsNaN("NaN", Double.NaN);
+            if (i == INT_SPACE || i == INT_TAB) {
+                i = (int) _inputBuffer[++_inputPtr];
+                if (i > INT_SPACE) {
+                    if (i == INT_SLASH || i == INT_HASH) {
+                        return _skipColon2(true);
+                    }
+                    ++_inputPtr;
+                    return i;
+                }
             }
-            _reportError("Non-standard token 'NaN': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
-            break;
-        case 'I':
-            _matchToken("Infinity", 1);
-            if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
-                return resetAsNaN("Infinity", Double.POSITIVE_INFINITY);
+            return _skipColon2(true); // true -> skipped colon
+        }
+        if (c == ' ' || c == '\t') {
+            c = _inputBuffer[++_inputPtr];
+        }
+        if (c == ':') {
+            int i = _inputBuffer[++_inputPtr];
+            if (i > INT_SPACE) {
+                if (i == INT_SLASH || i == INT_HASH) {
+                    return _skipColon2(true);
+                }
+                ++_inputPtr;
+                return i;
             }
-            _reportError("Non-standard token 'Infinity': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
-            break;
-        case '+': // note: '-' is taken as number
-            if (_inputPtr >= _inputEnd) {
-                if (!_loadMore()) {
-                    _reportInvalidEOFInValue(JsonToken.VALUE_NUMBER_INT);
+            if (i == INT_SPACE || i == INT_TAB) {
+                i = (int) _inputBuffer[++_inputPtr];
+                if (i > INT_SPACE) {
+                    if (i == INT_SLASH || i == INT_HASH) {
+                        return _skipColon2(true);
+                    }
+                    ++_inputPtr;
+                    return i;
                 }
             }
-            return _handleInvalidNumberStart(_inputBuffer[_inputPtr++], false);
+            return _skipColon2(true);
         }
-        // [core#77] Try to decode most likely token
-        if (Character.isJavaIdentifierStart(i)) {
-            _reportInvalidToken(""+((char) i), "('true', 'false' or 'null')");
+        return _skipColon2(false);
+    } /**
+     * We actually need to check the character value here
+     * (to see if we have \n following \r).
+     */
+    protected final void _skipCR() throws IOException {
+        if (_inputPtr < _inputEnd || _loadMore()) {
+            if (_inputBuffer[_inputPtr] == '\n') {
+                ++_inputPtr;
+            }
         }
-        // but if it doesn't look like a token:
-        _reportUnexpectedChar(i, "expected a valid value (number, String, array, object, 'true', 'false' or 'null')");
-        return null;
-    }
-
-    protected JsonToken _handleApos() throws IOException
+        ++_currInputRow;
+        _currInputRowStart = _inputPtr;
+    }private void _skipCComment() throws IOException
     {
-        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
-        int outPtr = _textBuffer.getCurrentSegmentSize();
-
-        while (true) {
-            if (_inputPtr >= _inputEnd) {
-                if (!_loadMore()) {
-                    _reportInvalidEOF(": was expecting closing quote for a string value",
-                            JsonToken.VALUE_STRING);
-                }
-            }
-            char c = _inputBuffer[_inputPtr++];
-            int i = (int) c;
-            if (i <= '\\') {
-                if (i == '\\') {
-                    /* Although chars outside of BMP are to be escaped as
-                     * an UTF-16 surrogate pair, does that affect decoding?
-                     * For now let's assume it does not.
-                     */
-                    c = _decodeEscaped();
-                } else if (i <= '\'') {
-                    if (i == '\'') {
+        // Ok: need the matching '*/'
+        while ((_inputPtr < _inputEnd) || _loadMore()) {
+            int i = (int) _inputBuffer[_inputPtr++];
+            if (i <= '*') {
+                if (i == '*') { // end?
+                    if ((_inputPtr >= _inputEnd) && !_loadMore()) {
                         break;
                     }
-                    if (i < INT_SPACE) {
-                        _throwUnquotedSpace(i, "string value");
+                    if (_inputBuffer[_inputPtr] == INT_SLASH) {
+                        ++_inputPtr;
+                        return;
+                    }
+                    continue;
+                }
+                if (i < INT_SPACE) {
+                    if (i == INT_LF) {
+                        ++_currInputRow;
+                        _currInputRowStart = _inputPtr;
+                    } else if (i == INT_CR) {
+                        _skipCR();
+                    } else if (i != INT_TAB) {
+                        _throwInvalidSpace(i);
                     }
                 }
             }
-            // Need more room?
-            if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
-                outPtr = 0;
-            }
-            // Ok, let's add char to output:
-            outBuf[outPtr++] = c;
         }
-        _textBuffer.setCurrentLength(outPtr);
-        return JsonToken.VALUE_STRING;
-    }
-
-    private String _handleOddName2(int startPtr, int hash, int[] codes) throws IOException
+        _reportInvalidEOF(" in a comment", null);
+    }private final int _skipAfterComma2() throws IOException
     {
-        _textBuffer.resetWithShared(_inputBuffer, startPtr, (_inputPtr - startPtr));
-        char[] outBuf = _textBuffer.getCurrentSegment();
-        int outPtr = _textBuffer.getCurrentSegmentSize();
-        final int maxCode = codes.length;
-
-        while (true) {
-            if (_inputPtr >= _inputEnd) {
-                if (!_loadMore()) { // acceptable for now (will error out later)
-                    break;
+        while (_inputPtr < _inputEnd || _loadMore()) {
+            int i = (int) _inputBuffer[_inputPtr++];
+            if (i > INT_SPACE) {
+                if (i == INT_SLASH) {
+                    _skipComment();
+                    continue;
+                }
+                if (i == INT_HASH) {
+                    if (_skipYAMLComment()) {
+                        continue;
+                    }
                 }
+                return i;
             }
-            char c = _inputBuffer[_inputPtr];
-            int i = (int) c;
-            if (i <= maxCode) {
-                if (codes[i] != 0) {
-                    break;
+            if (i < INT_SPACE) {
+                if (i == INT_LF) {
+                    ++_currInputRow;
+                    _currInputRowStart = _inputPtr;
+                } else if (i == INT_CR) {
+                    _skipCR();
+                } else if (i != INT_TAB) {
+                    _throwInvalidSpace(i);
                 }
-            } else if (!Character.isJavaIdentifierPart(c)) {
+            }
+        }
+        throw _constructError("Unexpected end-of-input within/between "+_parsingContext.typeDesc()+" entries");
+    }protected void _reportInvalidToken(String matchedPart) throws IOException {
+        _reportInvalidToken(matchedPart, "'null', 'true', 'false' or NaN");
+    }protected void _reportInvalidToken(String matchedPart, String msg) throws IOException
+    {
+        /* Let's just try to find what appears to be the token, using
+         * regular Java identifier character rules. It's just a heuristic,
+         * nothing fancy here.
+         */
+        StringBuilder sb = new StringBuilder(matchedPart);
+        while ((_inputPtr < _inputEnd) || _loadMore()) {
+            char c = _inputBuffer[_inputPtr];
+            if (!Character.isJavaIdentifierPart(c)) {
                 break;
             }
             ++_inputPtr;
-            hash = (hash * CharsToNameCanonicalizer.HASH_MULT) + i;
-            // Ok, let's add char to output:
-            outBuf[outPtr++] = c;
-
-            // Need more room?
-            if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
-                outPtr = 0;
+            sb.append(c);
+            if (sb.length() >= MAX_ERROR_TOKEN_LENGTH) {
+                sb.append("...");
+                break;
             }
         }
-        _textBuffer.setCurrentLength(outPtr);
-        {
-            TextBuffer tb = _textBuffer;
-            char[] buf = tb.getTextBuffer();
-            int start = tb.getTextOffset();
-            int len = tb.size();
-
-            return _symbols.findSymbol(buf, start, len, hash);
-        }
-    }
-
+        _reportError("Unrecognized token '%s': was expecting %s", sb, msg);
+    } /**
+     * Method called to release internal buffers owned by the base
+     * reader. This may be called along with {@link #_closeInput} (for
+     * example, when explicitly closing this reader instance), or
+     * separately (if need be).
+     */
     @Override
-    protected final void _finishString() throws IOException
+    protected void _releaseBuffers() throws IOException {
+        super._releaseBuffers();
+        // merge new symbols, if any
+        _symbols.release();
+        // and release buffers, if they are recyclable ones
+        if (_bufferRecyclable) {
+            char[] buf = _inputBuffer;
+            if (buf != null) {
+                _inputBuffer = null;
+                _ioContext.releaseTokenBuffer(buf);
+            }
+        }
+    }protected int _readBinary(Base64Variant b64variant, OutputStream out, byte[] buffer) throws IOException
     {
-        /* First: let's try to see if we have simple String value: one
-         * that does not cross input buffer boundary, and does not
-         * contain escape sequences.
-         */
-        int ptr = _inputPtr;
-        final int inputLen = _inputEnd;
-
-        if (ptr < inputLen) {
-            final int[] codes = _icLatin1;
-            final int maxCode = codes.length;
+        int outputPtr = 0;
+        final int outputEnd = buffer.length - 3;
+        int outputCount = 0;
 
+        while (true) {
+            // first, we'll skip preceding white space, if any
+            char ch;
             do {
-                int ch = _inputBuffer[ptr];
-                if (ch < maxCode && codes[ch] != 0) {
-                    if (ch == '"') {
-                        _textBuffer.resetWithShared(_inputBuffer, _inputPtr, (ptr-_inputPtr));
-                        _inputPtr = ptr+1;
-                        // Yes, we got it all
-                        return;
-                    }
+                if (_inputPtr >= _inputEnd) {
+                    _loadMoreGuaranteed();
+                }
+                ch = _inputBuffer[_inputPtr++];
+            } while (ch <= INT_SPACE);
+            int bits = b64variant.decodeBase64Char(ch);
+            if (bits < 0) { // reached the end, fair and square?
+                if (ch == '"') {
                     break;
                 }
-                ++ptr;
-            } while (ptr < inputLen);
-        }
+                bits = _decodeBase64Escape(b64variant, ch, 0);
+                if (bits < 0) { // white space to skip
+                    continue;
+                }
+            }
 
-        /* Either ran out of input, or bumped into an escape
-         * sequence...
-         */
-        _textBuffer.resetWithCopy(_inputBuffer, _inputPtr, (ptr-_inputPtr));
-        _inputPtr = ptr;
-        _finishString2();
-    }
+            // enough room? If not, flush
+            if (outputPtr > outputEnd) {
+                outputCount += outputPtr;
+                out.write(buffer, 0, outputPtr);
+                outputPtr = 0;
+            }
 
-    protected void _finishString2() throws IOException
-    {
-        char[] outBuf = _textBuffer.getCurrentSegment();
-        int outPtr = _textBuffer.getCurrentSegmentSize();
-        final int[] codes = _icLatin1;
-        final int maxCode = codes.length;
+            int decodedData = bits;
+
+            // then second base64 char; can't get padding yet, nor ws
 
-        while (true) {
             if (_inputPtr >= _inputEnd) {
-                if (!_loadMore()) {
-                    _reportInvalidEOF(": was expecting closing quote for a string value",
-                            JsonToken.VALUE_STRING);
-                }
-            }
-            char c = _inputBuffer[_inputPtr++];
-            int i = (int) c;
-            if (i < maxCode && codes[i] != 0) {
-                if (i == INT_QUOTE) {
-                    break;
-                } else if (i == INT_BACKSLASH) {
-                    /* Although chars outside of BMP are to be escaped as
-                     * an UTF-16 surrogate pair, does that affect decoding?
-                     * For now let's assume it does not.
-                     */
-                    c = _decodeEscaped();
-                } else if (i < INT_SPACE) {
-                    _throwUnquotedSpace(i, "string value");
-                } // anything else?
+                _loadMoreGuaranteed();
             }
-            // Need more room?
-            if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
-                outPtr = 0;
+            ch = _inputBuffer[_inputPtr++];
+            bits = b64variant.decodeBase64Char(ch);
+            if (bits < 0) {
+                bits = _decodeBase64Escape(b64variant, ch, 1);
             }
-            // Ok, let's add char to output:
-            outBuf[outPtr++] = c;
-        }
-        _textBuffer.setCurrentLength(outPtr);
-    }
-
-    /**
-     * Method called to skim through rest of unparsed String value,
-     * if it is not needed. This can be done bit faster if contents
-     * need not be stored for future access.
-     */
-    protected final void _skipString() throws IOException
-    {
-        _tokenIncomplete = false;
-
-        int inPtr = _inputPtr;
-        int inLen = _inputEnd;
-        char[] inBuf = _inputBuffer;
+            decodedData = (decodedData << 6) | bits;
 
-        while (true) {
-            if (inPtr >= inLen) {
-                _inputPtr = inPtr;
-                if (!_loadMore()) {
-                    _reportInvalidEOF(": was expecting closing quote for a string value",
-                            JsonToken.VALUE_STRING);
-                }
-                inPtr = _inputPtr;
-                inLen = _inputEnd;
+            // third base64 char; can be padding, but not ws
+            if (_inputPtr >= _inputEnd) {
+                _loadMoreGuaranteed();
             }
-            char c = inBuf[inPtr++];
-            int i = (int) c;
-            if (i <= INT_BACKSLASH) {
-                if (i == INT_BACKSLASH) {
-                    // Although chars outside of BMP are to be escaped as an UTF-16 surrogate pair,
-                    // does that affect decoding? For now let's assume it does not.
-                    _inputPtr = inPtr;
-                    /*c = */ _decodeEscaped();
-                    inPtr = _inputPtr;
-                    inLen = _inputEnd;
-                } else if (i <= INT_QUOTE) {
-                    if (i == INT_QUOTE) {
-                        _inputPtr = inPtr;
+            ch = _inputBuffer[_inputPtr++];
+            bits = b64variant.decodeBase64Char(ch);
+
+            // First branch: can get padding (-> 1 byte)
+            if (bits < 0) {
+                if (bits != Base64Variant.BASE64_VALUE_PADDING) {
+                    // as per [JACKSON-631], could also just be 'missing'  padding
+                    if (ch == '"' && !b64variant.usesPadding()) {
+                        decodedData >>= 4;
+                        buffer[outputPtr++] = (byte) decodedData;
                         break;
                     }
-                    if (i < INT_SPACE) {
-                        _inputPtr = inPtr;
-                        _throwUnquotedSpace(i, "string value");
+                    bits = _decodeBase64Escape(b64variant, ch, 2);
+                }
+                if (bits == Base64Variant.BASE64_VALUE_PADDING) {
+                    // Ok, must get padding
+                    if (_inputPtr >= _inputEnd) {
+                        _loadMoreGuaranteed();
+                    }
+                    ch = _inputBuffer[_inputPtr++];
+                    if (!b64variant.usesPaddingChar(ch)) {
+                        throw reportInvalidBase64Char(b64variant, ch, 3, "expected padding character '"+b64variant.getPaddingChar()+"'");
                     }
+                    // Got 12 bits, only need 8, need to shift
+                    decodedData >>= 4;
+                    buffer[outputPtr++] = (byte) decodedData;
+                    continue;
                 }
             }
-        }
-    }
-
-    /*
-    /**********************************************************
-    /* Internal methods, other parsing
-    /**********************************************************
-     */
-
-    /**
-     * We actually need to check the character value here
-     * (to see if we have \n following \r).
-     */
-    protected final void _skipCR() throws IOException {
-        if (_inputPtr < _inputEnd || _loadMore()) {
-            if (_inputBuffer[_inputPtr] == '\n') {
-                ++_inputPtr;
+            // Nope, 2 or 3 bytes
+            decodedData = (decodedData << 6) | bits;
+            // fourth and last base64 char; can be padding, but not ws
+            if (_inputPtr >= _inputEnd) {
+                _loadMoreGuaranteed();
             }
-        }
-        ++_currInputRow;
-        _currInputRowStart = _inputPtr;
-    }
-
-    private final int _skipColon() throws IOException
-    {
-        if ((_inputPtr + 4) >= _inputEnd) {
-            return _skipColon2(false);
-        }
-        char c = _inputBuffer[_inputPtr];
-        if (c == ':') { // common case, no leading space
-            int i = _inputBuffer[++_inputPtr];
-            if (i > INT_SPACE) { // nor trailing
-                if (i == INT_SLASH || i == INT_HASH) {
-                    return _skipColon2(true);
-                }
-                ++_inputPtr;
-                return i;
-            }
-            if (i == INT_SPACE || i == INT_TAB) {
-                i = (int) _inputBuffer[++_inputPtr];
-                if (i > INT_SPACE) {
-                    if (i == INT_SLASH || i == INT_HASH) {
-                        return _skipColon2(true);
+            ch = _inputBuffer[_inputPtr++];
+            bits = b64variant.decodeBase64Char(ch);
+            if (bits < 0) {
+                if (bits != Base64Variant.BASE64_VALUE_PADDING) {
+                    // as per [JACKSON-631], could also just be 'missing'  padding
+                    if (ch == '"' && !b64variant.usesPadding()) {
+                        decodedData >>= 2;
+                        buffer[outputPtr++] = (byte) (decodedData >> 8);
+                        buffer[outputPtr++] = (byte) decodedData;
+                        break;
                     }
-                    ++_inputPtr;
-                    return i;
+                    bits = _decodeBase64Escape(b64variant, ch, 3);
+                }
+                if (bits == Base64Variant.BASE64_VALUE_PADDING) {
+                    /* With padding we only get 2 bytes; but we have
+                     * to shift it a bit so it is identical to triplet
+                     * case with partial output.
+                     * 3 chars gives 3x6 == 18 bits, of which 2 are
+                     * dummies, need to discard:
+                     */
+                    decodedData >>= 2;
+                    buffer[outputPtr++] = (byte) (decodedData >> 8);
+                    buffer[outputPtr++] = (byte) decodedData;
+                    continue;
                 }
             }
-            return _skipColon2(true); // true -> skipped colon
+            // otherwise, our triplet is now complete
+            decodedData = (decodedData << 6) | bits;
+            buffer[outputPtr++] = (byte) (decodedData >> 16);
+            buffer[outputPtr++] = (byte) (decodedData >> 8);
+            buffer[outputPtr++] = (byte) decodedData;
         }
-        if (c == ' ' || c == '\t') {
-            c = _inputBuffer[++_inputPtr];
+        _tokenIncomplete = false;
+        if (outputPtr > 0) {
+            outputCount += outputPtr;
+            out.write(buffer, 0, outputPtr);
         }
-        if (c == ':') {
-            int i = _inputBuffer[++_inputPtr];
-            if (i > INT_SPACE) {
-                if (i == INT_SLASH || i == INT_HASH) {
-                    return _skipColon2(true);
-                }
-                ++_inputPtr;
-                return i;
+        return outputCount;
+    } /**
+     * Initial parsing method for number values. It needs to be able
+     * to parse enough input to be able to determine whether the
+     * value is to be considered a simple integer value, or a more
+     * generic decimal value: latter of which needs to be expressed
+     * as a floating point number. The basic rule is that if the number
+     * has no fractional or exponential part, it is an integer; otherwise
+     * a floating point number.
+     *<p>
+     * Because much of input has to be processed in any case, no partial
+     * parsing is done: all input text will be stored for further
+     * processing. However, actual numeric value conversion will be
+     * deferred, since it is usually the most complicated and costliest
+     * part of processing.
+     */
+    protected final JsonToken _parsePosNumber(int ch) throws IOException
+    {
+        /* Although we will always be complete with respect to textual
+         * representation (that is, all characters will be parsed),
+         * actual conversion to a number is deferred. Thus, need to
+         * note that no representations are valid yet
+         */
+        int ptr = _inputPtr;
+        int startPtr = ptr-1; // to include digit already read
+        final int inputLen = _inputEnd;
+
+        // One special case, leading zero(es):
+        if (ch == INT_0) {
+            return _parseNumber2(false, startPtr);
+        }
+
+        /* First, let's see if the whole number is contained within
+         * the input buffer unsplit. This should be the common case;
+         * and to simplify processing, we will just reparse contents
+         * in the alternative case (number split on buffer boundary)
+         */
+
+        int intLen = 1; // already got one
+
+        // First let's get the obligatory integer part:
+        int_loop:
+        while (true) {
+            if (ptr >= inputLen) {
+                _inputPtr = startPtr;
+                return _parseNumber2(false, startPtr);
             }
-            if (i == INT_SPACE || i == INT_TAB) {
-                i = (int) _inputBuffer[++_inputPtr];
-                if (i > INT_SPACE) {
-                    if (i == INT_SLASH || i == INT_HASH) {
-                        return _skipColon2(true);
-                    }
-                    ++_inputPtr;
-                    return i;
-                }
+            ch = (int) _inputBuffer[ptr++];
+            if (ch < INT_0 || ch > INT_9) {
+                break int_loop;
             }
-            return _skipColon2(true);
+            ++intLen;
         }
-        return _skipColon2(false);
-    }
-
-    private final int _skipColon2(boolean gotColon) throws IOException
+        if (ch == INT_PERIOD || ch == INT_e || ch == INT_E) {
+            _inputPtr = ptr;
+            return _parseFloat(ch, startPtr, ptr, false, intLen);
+        }
+        // Got it all: let's add to text buffer for parsing, access
+        --ptr; // need to push back following separator
+        _inputPtr = ptr;
+        // As per #105, need separating space between root values; check here
+        if (_parsingContext.inRoot()) {
+            _verifyRootSpace(ch);
+        }
+        int len = ptr-startPtr;
+        _textBuffer.resetWithShared(_inputBuffer, startPtr, len);
+        return resetInt(false, intLen);
+    } /**
+     * Method called to parse a number, when the primary parse
+     * method has failed to parse it, due to it being split on
+     * buffer boundary. As a result code is very similar, except
+     * that it has to explicitly copy contents to the text buffer
+     * instead of just sharing the main input buffer.
+     */
+    private final JsonToken _parseNumber2(boolean neg, int startPtr) throws IOException
     {
-        while (_inputPtr < _inputEnd || _loadMore()) {
-            int i = (int) _inputBuffer[_inputPtr++];
-            if (i > INT_SPACE) {
-                if (i == INT_SLASH) {
-                    _skipComment();
-                    continue;
-                }
-                if (i == INT_HASH) {
-                    if (_skipYAMLComment()) {
-                        continue;
-                    }
-                }
-                if (gotColon) {
-                    return i;
-                }
-                if (i != INT_COLON) {
-                    _reportUnexpectedChar(i, "was expecting a colon to separate field name and value");
-                }
-                gotColon = true;
-                continue;
+        _inputPtr = neg ? (startPtr+1) : startPtr;
+        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
+        int outPtr = 0;
+
+        // Need to prepend sign?
+        if (neg) {
+            outBuf[outPtr++] = '-';
+        }
+
+        // This is the place to do leading-zero check(s) too:
+        int intLen = 0;
+        char c = (_inputPtr < _inputEnd) ? _inputBuffer[_inputPtr++]
+                : getNextChar("No digit following minus sign", JsonToken.VALUE_NUMBER_INT);
+        if (c == '0') {
+            c = _verifyNoLeadingZeroes();
+        }
+        boolean eof = false;
+
+        // Ok, first the obligatory integer part:
+        int_loop:
+        while (c >= '0' && c <= '9') {
+            ++intLen;
+            if (outPtr >= outBuf.length) {
+                outBuf = _textBuffer.finishCurrentSegment();
+                outPtr = 0;
             }
-            if (i < INT_SPACE) {
-                if (i == INT_LF) {
-                    ++_currInputRow;
-                    _currInputRowStart = _inputPtr;
-                } else if (i == INT_CR) {
-                    _skipCR();
-                } else if (i != INT_TAB) {
-                    _throwInvalidSpace(i);
-                }
+            outBuf[outPtr++] = c;
+            if (_inputPtr >= _inputEnd && !_loadMore()) {
+                // EOF is legal for main level int values
+                c = CHAR_NULL;
+                eof = true;
+                break int_loop;
             }
+            c = _inputBuffer[_inputPtr++];
+        }
+        // Also, integer part is not optional
+        if (intLen == 0) {
+            return _handleInvalidNumberStart(c, neg);
         }
-        _reportInvalidEOF(" within/between "+_parsingContext.typeDesc()+" entries",
-                null);
-        return -1;
-    }
 
-    // Variant called when we know there's at least 4 more bytes available
-    private final int _skipColonFast(int ptr) throws IOException
-    {
-        int i = (int) _inputBuffer[ptr++];
-        if (i == INT_COLON) { // common case, no leading space
-            i = _inputBuffer[ptr++];
-            if (i > INT_SPACE) { // nor trailing
-                if (i != INT_SLASH && i != INT_HASH) {
-                    _inputPtr = ptr;
-                    return i;
+        int fractLen = 0;
+        // And then see if we get other parts
+        if (c == '.') { // yes, fraction
+            if (outPtr >= outBuf.length) {
+                outBuf = _textBuffer.finishCurrentSegment();
+                outPtr = 0;
+            }
+            outBuf[outPtr++] = c;
+
+            fract_loop:
+            while (true) {
+                if (_inputPtr >= _inputEnd && !_loadMore()) {
+                    eof = true;
+                    break fract_loop;
                 }
-            } else if (i == INT_SPACE || i == INT_TAB) {
-                i = (int) _inputBuffer[ptr++];
-                if (i > INT_SPACE) {
-                    if (i != INT_SLASH && i != INT_HASH) {
-                        _inputPtr = ptr;
-                        return i;
-                    }
+                c = _inputBuffer[_inputPtr++];
+                if (c < INT_0 || c > INT_9) {
+                    break fract_loop;
+                }
+                ++fractLen;
+                if (outPtr >= outBuf.length) {
+                    outBuf = _textBuffer.finishCurrentSegment();
+                    outPtr = 0;
                 }
+                outBuf[outPtr++] = c;
+            }
+            // must be followed by sequence of ints, one minimum
+            if (fractLen == 0) {
+                reportUnexpectedNumberChar(c, "Decimal point not followed by a digit");
             }
-            _inputPtr = ptr-1;
-            return _skipColon2(true); // true -> skipped colon
         }
-        if (i == INT_SPACE || i == INT_TAB) {
-            i = _inputBuffer[ptr++];
-        }
-        boolean gotColon = (i == INT_COLON);
-        if (gotColon) {
-            i = _inputBuffer[ptr++];
-            if (i > INT_SPACE) {
-                if (i != INT_SLASH && i != INT_HASH) {
-                    _inputPtr = ptr;
-                    return i;
+
+        int expLen = 0;
+        if (c == 'e' || c == 'E') { // exponent?
+            if (outPtr >= outBuf.length) {
+                outBuf = _textBuffer.finishCurrentSegment();
+                outPtr = 0;
+            }
+            outBuf[outPtr++] = c;
+            // Not optional, can require that we get one more char
+            c = (_inputPtr < _inputEnd) ? _inputBuffer[_inputPtr++]
+                : getNextChar("expected a digit for number exponent");
+            // Sign indicator?
+            if (c == '-' || c == '+') {
+                if (outPtr >= outBuf.length) {
+                    outBuf = _textBuffer.finishCurrentSegment();
+                    outPtr = 0;
                 }
-            } else if (i == INT_SPACE || i == INT_TAB) {
-                i = (int) _inputBuffer[ptr++];
-                if (i > INT_SPACE) {
-                    if (i != INT_SLASH && i != INT_HASH) {
-                        _inputPtr = ptr;
-                        return i;
-                    }
+                outBuf[outPtr++] = c;
+                // Likewise, non optional:
+                c = (_inputPtr < _inputEnd) ? _inputBuffer[_inputPtr++]
+                    : getNextChar("expected a digit for number exponent");
+            }
+
+            exp_loop:
+            while (c <= INT_9 && c >= INT_0) {
+                ++expLen;
+                if (outPtr >= outBuf.length) {
+                    outBuf = _textBuffer.finishCurrentSegment();
+                    outPtr = 0;
+                }
+                outBuf[outPtr++] = c;
+                if (_inputPtr >= _inputEnd && !_loadMore()) {
+                    eof = true;
+                    break exp_loop;
                 }
+                c = _inputBuffer[_inputPtr++];
+            }
+            // must be followed by sequence of ints, one minimum
+            if (expLen == 0) {
+                reportUnexpectedNumberChar(c, "Exponent indicator not followed by a digit");
             }
         }
-        _inputPtr = ptr-1;
-        return _skipColon2(gotColon);
-    }
 
-    // Primary loop: no reloading, comment handling
-    private final int _skipComma(int i) throws IOException
+        // Ok; unless we hit end-of-input, need to push last char read back
+        if (!eof) {
+            --_inputPtr;
+            if (_parsingContext.inRoot()) {
+                _verifyRootSpace(c);
+            }
+        }
+        _textBuffer.setCurrentLength(outPtr);
+        // And there we have it!
+        return reset(neg, intLen, fractLen, expLen);
+    }protected final JsonToken _parseNegNumber() throws IOException
     {
-        if (i != INT_COMMA) {
-            _reportUnexpectedChar(i, "was expecting comma to separate "+_parsingContext.typeDesc()+" entries");
+        int ptr = _inputPtr;
+        int startPtr = ptr-1; // to include sign/digit already read
+        final int inputLen = _inputEnd;
+
+        if (ptr >= inputLen) {
+            return _parseNumber2(true, startPtr);
         }
-        while (_inputPtr < _inputEnd) {
-            i = (int) _inputBuffer[_inputPtr++];
-            if (i > INT_SPACE) {
-                if (i == INT_SLASH || i == INT_HASH) {
-                    --_inputPtr;
-                    return _skipAfterComma2();
-                }
-                return i;
+        int ch = _inputBuffer[ptr++];
+        // First check: must have a digit to follow minus sign
+        if (ch > INT_9 || ch < INT_0) {
+            _inputPtr = ptr;
+            return _handleInvalidNumberStart(ch, true);
+        }
+        // One special case, leading zero(es):
+        if (ch == INT_0) {
+            return _parseNumber2(true, startPtr);
+        }
+        int intLen = 1; // already got one
+
+        // First let's get the obligatory integer part:
+        int_loop:
+        while (true) {
+            if (ptr >= inputLen) {
+                return _parseNumber2(true, startPtr);
             }
-            if (i < INT_SPACE) {
-                if (i == INT_LF) {
-                    ++_currInputRow;
-                    _currInputRowStart = _inputPtr;
-                } else if (i == INT_CR) {
-                    _skipCR();
-                } else if (i != INT_TAB) {
-                    _throwInvalidSpace(i);
-                }
+            ch = (int) _inputBuffer[ptr++];
+            if (ch < INT_0 || ch > INT_9) {
+                break int_loop;
             }
+            ++intLen;
         }
-        return _skipAfterComma2();
-    }
 
-    private final int _skipAfterComma2() throws IOException
+        if (ch == INT_PERIOD || ch == INT_e || ch == INT_E) {
+            _inputPtr = ptr;
+            return _parseFloat(ch, startPtr, ptr, true, intLen);
+        }
+        --ptr;
+        _inputPtr = ptr;
+        if (_parsingContext.inRoot()) {
+            _verifyRootSpace(ch);
+        }
+        int len = ptr-startPtr;
+        _textBuffer.resetWithShared(_inputBuffer, startPtr, len);
+        return resetInt(true, intLen);
+    }private String _parseName2(int startPtr, int hash, int endChar) throws IOException
     {
-        while (_inputPtr < _inputEnd || _loadMore()) {
-            int i = (int) _inputBuffer[_inputPtr++];
-            if (i > INT_SPACE) {
-                if (i == INT_SLASH) {
-                    _skipComment();
-                    continue;
-                }
-                if (i == INT_HASH) {
-                    if (_skipYAMLComment()) {
-                        continue;
-                    }
+        _textBuffer.resetWithShared(_inputBuffer, startPtr, (_inputPtr - startPtr));
+
+        /* Output pointers; calls will also ensure that the buffer is
+         * not shared and has room for at least one more char.
+         */
+        char[] outBuf = _textBuffer.getCurrentSegment();
+        int outPtr = _textBuffer.getCurrentSegmentSize();
+
+        while (true) {
+            if (_inputPtr >= _inputEnd) {
+                if (!_loadMore()) {
+                    _reportInvalidEOF(" in field name", JsonToken.FIELD_NAME);
                 }
-                return i;
             }
-            if (i < INT_SPACE) {
-                if (i == INT_LF) {
-                    ++_currInputRow;
-                    _currInputRowStart = _inputPtr;
-                } else if (i == INT_CR) {
-                    _skipCR();
-                } else if (i != INT_TAB) {
-                    _throwInvalidSpace(i);
+            char c = _inputBuffer[_inputPtr++];
+            int i = (int) c;
+            if (i <= INT_BACKSLASH) {
+                if (i == INT_BACKSLASH) {
+                    /* Although chars outside of BMP are to be escaped as
+                     * an UTF-16 surrogate pair, does that affect decoding?
+                     * For now let's assume it does not.
+                     */
+                    c = _decodeEscaped();
+                } else if (i <= endChar) {
+                    if (i == endChar) {
+                        break;
+                    }
+                    if (i < INT_SPACE) {
+                        _throwUnquotedSpace(i, "name");
+                    }
                 }
             }
-        }
-        throw _constructError("Unexpected end-of-input within/between "+_parsingContext.typeDesc()+" entries");
-    }
+            hash = (hash * CharsToNameCanonicalizer.HASH_MULT) + c;
+            // Ok, let's add char to output:
+            outBuf[outPtr++] = c;
 
-    private final int _skipWSOrEnd() throws IOException
-    {
-        // Let's handle first character separately since it is likely that
-        // it is either non-whitespace; or we have longer run of white space
-        if (_inputPtr >= _inputEnd) {
-            if (!_loadMore()) {
-                return _eofAsNextChar();
+            // Need more room?
+            if (outPtr >= outBuf.length) {
+                outBuf = _textBuffer.finishCurrentSegment();
+                outPtr = 0;
             }
         }
-        int i = _inputBuffer[_inputPtr++];
-        if (i > INT_SPACE) {
-            if (i == INT_SLASH || i == INT_HASH) {
-                --_inputPtr;
-                return _skipWSOrEnd2();
-            }
-            return i;
+        _textBuffer.setCurrentLength(outPtr);
+        {
+            TextBuffer tb = _textBuffer;
+            char[] buf = tb.getTextBuffer();
+            int start = tb.getTextOffset();
+            int len = tb.size();
+            return _symbols.findSymbol(buf, start, len, hash);
         }
-        if (i != INT_SPACE) {
-            if (i == INT_LF) {
-                ++_currInputRow;
-                _currInputRowStart = _inputPtr;
-            } else if (i == INT_CR) {
-                _skipCR();
-            } else if (i != INT_TAB) {
-                _throwInvalidSpace(i);
+    }protected final String _parseName() throws IOException
+    {
+        // First: let's try to see if we have a simple name: one that does
+        // not cross input buffer boundary, and does not contain escape sequences.
+        int ptr = _inputPtr;
+        int hash = _hashSeed;
+        final int[] codes = _icLatin1;
+
+        while (ptr < _inputEnd) {
+            int ch = _inputBuffer[ptr];
+            if (ch < codes.length && codes[ch] != 0) {
+                if (ch == '"') {
+                    int start = _inputPtr;
+                    _inputPtr = ptr+1; // to skip the quote
+                    return _symbols.findSymbol(_inputBuffer, start, ptr - start, hash);
+                }
+                break;
             }
+            hash = (hash * CharsToNameCanonicalizer.HASH_MULT) + ch;
+            ++ptr;
         }
+        int start = _inputPtr;
+        _inputPtr = ptr;
+        return _parseName2(start, hash, INT_QUOTE);
+    }private final JsonToken _parseFloat(int ch, int startPtr, int ptr, boolean neg, int intLen)
+        throws IOException
+    {
+        final int inputLen = _inputEnd;
+        int fractLen = 0;
 
-        while (_inputPtr < _inputEnd) {
-            i = (int) _inputBuffer[_inputPtr++];
-            if (i > INT_SPACE) {
-                if (i == INT_SLASH || i == INT_HASH) {
-                    --_inputPtr;
-                    return _skipWSOrEnd2();
+        // And then see if we get other parts
+        if (ch == '.') { // yes, fraction
+            fract_loop:
+            while (true) {
+                if (ptr >= inputLen) {
+                    return _parseNumber2(neg, startPtr);
                 }
-                return i;
+                ch = (int) _inputBuffer[ptr++];
+                if (ch < INT_0 || ch > INT_9) {
+                    break fract_loop;
+                }
+                ++fractLen;
             }
-            if (i != INT_SPACE) {
-                if (i == INT_LF) {
-                    ++_currInputRow;
-                    _currInputRowStart = _inputPtr;
-                } else if (i == INT_CR) {
-                    _skipCR();
-                } else if (i != INT_TAB) {
-                    _throwInvalidSpace(i);
+            // must be followed by sequence of ints, one minimum
+            if (fractLen == 0) {
+                reportUnexpectedNumberChar(ch, "Decimal point not followed by a digit");
+            }
+        }
+        int expLen = 0;
+        if (ch == 'e' || ch == 'E') { // and/or exponent
+            if (ptr >= inputLen) {
+                _inputPtr = startPtr;
+                return _parseNumber2(neg, startPtr);
+            }
+            // Sign indicator?
+            ch = (int) _inputBuffer[ptr++];
+            if (ch == INT_MINUS || ch == INT_PLUS) { // yup, skip for now
+                if (ptr >= inputLen) {
+                    _inputPtr = startPtr;
+                    return _parseNumber2(neg, startPtr);
+                }
+                ch = (int) _inputBuffer[ptr++];
+            }
+            while (ch <= INT_9 && ch >= INT_0) {
+                ++expLen;
+                if (ptr >= inputLen) {
+                    _inputPtr = startPtr;
+                    return _parseNumber2(neg, startPtr);
+                }
+                ch = (int) _inputBuffer[ptr++];
+            }
+            // must be followed by sequence of ints, one minimum
+            if (expLen == 0) {
+                reportUnexpectedNumberChar(ch, "Exponent indicator not followed by a digit");
+            }
+        }
+        --ptr; // need to push back following separator
+        _inputPtr = ptr;
+        // As per #105, need separating space between root values; check here
+        if (_parsingContext.inRoot()) {
+            _verifyRootSpace(ch);
+        }
+        int len = ptr-startPtr;
+        _textBuffer.resetWithShared(_inputBuffer, startPtr, len);
+        // And there we have it!
+        return resetFloat(neg, intLen, fractLen, expLen);
+    }protected String _parseAposName() throws IOException
+    {
+        // Note: mostly copy of_parseFieldName
+        int ptr = _inputPtr;
+        int hash = _hashSeed;
+        final int inputLen = _inputEnd;
+
+        if (ptr < inputLen) {
+            final int[] codes = _icLatin1;
+            final int maxCode = codes.length;
+
+            do {
+                int ch = _inputBuffer[ptr];
+                if (ch == '\'') {
+                    int start = _inputPtr;
+                    _inputPtr = ptr+1; // to skip the quote
+                    return _symbols.findSymbol(_inputBuffer, start, ptr - start, hash);
+                }
+                if (ch < maxCode && codes[ch] != 0) {
+                    break;
+                }
+                hash = (hash * CharsToNameCanonicalizer.HASH_MULT) + ch;
+                ++ptr;
+            } while (ptr < inputLen);
+        }
+
+        int start = _inputPtr;
+        _inputPtr = ptr;
+
+        return _parseName2(start, hash, '\'');
+    }private final JsonToken _nextTokenNotInObject(int i) throws IOException
+    {
+        if (i == INT_QUOTE) {
+            _tokenIncomplete = true;
+            return (_currToken = JsonToken.VALUE_STRING);
+        }
+        switch (i) {
+        case '[':
+            _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            return (_currToken = JsonToken.START_ARRAY);
+        case '{':
+            _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            return (_currToken = JsonToken.START_OBJECT);
+        case 't':
+            _matchToken("true", 1);
+            return (_currToken = JsonToken.VALUE_TRUE);
+        case 'f':
+            _matchToken("false", 1);
+            return (_currToken = JsonToken.VALUE_FALSE);
+        case 'n':
+            _matchToken("null", 1);
+            return (_currToken = JsonToken.VALUE_NULL);
+        case '-':
+            return (_currToken = _parseNegNumber());
+            /* Should we have separate handling for plus? Although
+             * it is not allowed per se, it may be erroneously used,
+             * and could be indicated by a more specific error message.
+             */
+        case '0':
+        case '1':
+        case '2':
+        case '3':
+        case '4':
+        case '5':
+        case '6':
+        case '7':
+        case '8':
+        case '9':
+            return (_currToken = _parsePosNumber(i));
+        /*
+         * This check proceeds only if the Feature.ALLOW_MISSING_VALUES is enabled
+         * The Check is for missing values. Incase of missing values in an array, the next token will be either ',' or ']'.
+         * This case, decrements the already incremented _inputPtr in the buffer in case of comma(,)
+         * so that the existing flow goes back to checking the next token which will be comma again and
+         * it continues the parsing.
+         * Also the case returns NULL as current token in case of ',' or ']'.
+         */
+        case ',':
+        case ']':
+        	if(isEnabled(Feature.ALLOW_MISSING_VALUES)) {
+        		_inputPtr--;
+        		return (_currToken = JsonToken.VALUE_NULL);
+        	}
+        }
+        return (_currToken = _handleOddValue(i));
+    }private final JsonToken _nextAfterName()
+    {
+        _nameCopied = false; // need to invalidate if it was copied
+        JsonToken t = _nextToken;
+        _nextToken = null;
+
+// !!! 16-Nov-2015, tatu: TODO: fix [databind#37], copy next location to current here
+
+        // Also: may need to start new context?
+        if (t == JsonToken.START_ARRAY) {
+            _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+        } else if (t == JsonToken.START_OBJECT) {
+            _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+        }
+        return (_currToken = t);
+    }private final void _matchTrue() throws IOException {
+        int ptr = _inputPtr;
+        if ((ptr + 3) < _inputEnd) {
+            final char[] b = _inputBuffer;
+            if (b[ptr] == 'r' && b[++ptr] == 'u' && b[++ptr] == 'e') {
+                char c = b[++ptr];
+                if (c < '0' || c == ']' || c == '}') { // expected/allowed chars
+                    _inputPtr = ptr;
+                    return;
+                }
+            }
+        }
+        // buffer boundary, or problem, offline
+        _matchToken("true", 1);
+    } /**
+     * Helper method for checking whether input matches expected token
+     */
+    protected final void _matchToken(String matchStr, int i) throws IOException
+    {
+        final int len = matchStr.length();
+
+        do {
+            if (_inputPtr >= _inputEnd) {
+                if (!_loadMore()) {
+                    _reportInvalidToken(matchStr.substring(0, i));
+                }
+            }
+            if (_inputBuffer[_inputPtr] != matchStr.charAt(i)) {
+                _reportInvalidToken(matchStr.substring(0, i));
+            }
+            ++_inputPtr;
+        } while (++i < len);
+
+        // but let's also ensure we either get EOF, or non-alphanum char...
+        if (_inputPtr >= _inputEnd) {
+            if (!_loadMore()) {
+                return;
+            }
+        }
+        char c = _inputBuffer[_inputPtr];
+        if (c < '0' || c == ']' || c == '}') { // expected/allowed chars
+            return;
+        }
+        // if Java letter, it's a problem tho
+        if (Character.isJavaIdentifierPart(c)) {
+            _reportInvalidToken(matchStr.substring(0, i));
+        }
+        return;
+    }private final void _matchNull() throws IOException {
+        int ptr = _inputPtr;
+        if ((ptr + 3) < _inputEnd) {
+            final char[] b = _inputBuffer;
+            if (b[ptr] == 'u' && b[++ptr] == 'l' && b[++ptr] == 'l') {
+                char c = b[++ptr];
+                if (c < '0' || c == ']' || c == '}') { // expected/allowed chars
+                    _inputPtr = ptr;
+                    return;
+                }
+            }
+        }
+        // buffer boundary, or problem, offline
+        _matchToken("null", 1);
+    }private final void _matchFalse() throws IOException {
+        int ptr = _inputPtr;
+        if ((ptr + 4) < _inputEnd) {
+            final char[] b = _inputBuffer;
+            if (b[ptr] == 'a' && b[++ptr] == 'l' && b[++ptr] == 's' && b[++ptr] == 'e') {
+                char c = b[++ptr];
+                if (c < '0' || c == ']' || c == '}') { // expected/allowed chars
+                    _inputPtr = ptr;
+                    return;
+                }
+            }
+        }
+        // buffer boundary, or problem, offline
+        _matchToken("false", 1);
+    }protected void _loadMoreGuaranteed() throws IOException {
+        if (!_loadMore()) { _reportInvalidEOF(); }
+    }protected boolean _loadMore() throws IOException
+    {
+        final int bufSize = _inputEnd;
+
+        _currInputProcessed += bufSize;
+        _currInputRowStart -= bufSize;
+
+        // 26-Nov-2015, tatu: Since name-offset requires it too, must offset
+        //   this increase to avoid "moving" name-offset, resulting most likely
+        //   in negative value, which is fine as combine value remains unchanged.
+        _nameStartOffset -= bufSize;
+
+        if (_reader != null) {
+            int count = _reader.read(_inputBuffer, 0, _inputBuffer.length);
+            if (count > 0) {
+                _inputPtr = 0;
+                _inputEnd = count;
+                return true;
+            }
+            // End of input
+            _closeInput();
+            // Should never return 0, so let's fail
+            if (count == 0) {
+                throw new IOException("Reader returned 0 characters when trying to read "+_inputEnd);
+            }
+        }
+        return false;
+    }private final void _isNextTokenNameYes(int i) throws IOException
+    {
+        _currToken = JsonToken.FIELD_NAME;
+        _updateLocation();
+
+        switch (i) {
+        case '"':
+            _tokenIncomplete = true;
+            _nextToken = JsonToken.VALUE_STRING;
+            return;
+        case '[':
+            _nextToken = JsonToken.START_ARRAY;
+            return;
+        case '{':
+            _nextToken = JsonToken.START_OBJECT;
+            return;
+        case 't':
+            _matchToken("true", 1);
+            _nextToken = JsonToken.VALUE_TRUE;
+            return;
+        case 'f':
+            _matchToken("false", 1);
+            _nextToken = JsonToken.VALUE_FALSE;
+            return;
+        case 'n':
+            _matchToken("null", 1);
+            _nextToken = JsonToken.VALUE_NULL;
+            return;
+        case '-':
+            _nextToken = _parseNegNumber();
+            return;
+        case '0':
+        case '1':
+        case '2':
+        case '3':
+        case '4':
+        case '5':
+        case '6':
+        case '7':
+        case '8':
+        case '9':
+            _nextToken = _parsePosNumber(i);
+            return;
+        }
+        _nextToken = _handleOddValue(i);
+    }protected boolean _isNextTokenNameMaybe(int i, String nameToMatch) throws IOException
+    {
+        // // // and this is back to standard nextToken()
+        String name = (i == INT_QUOTE) ? _parseName() : _handleOddName(i);
+        _parsingContext.setCurrentName(name);
+        _currToken = JsonToken.FIELD_NAME;
+        i = _skipColon();
+        _updateLocation();
+        if (i == INT_QUOTE) {
+            _tokenIncomplete = true;
+            _nextToken = JsonToken.VALUE_STRING;
+            return nameToMatch.equals(name);
+        }
+        // Ok: we must have a value... what is it?
+        JsonToken t;
+        switch (i) {
+        case '-':
+            t = _parseNegNumber();
+            break;
+        case '0':
+        case '1':
+        case '2':
+        case '3':
+        case '4':
+        case '5':
+        case '6':
+        case '7':
+        case '8':
+        case '9':
+            t = _parsePosNumber(i);
+            break;
+        case 'f':
+            _matchFalse();
+            t = JsonToken.VALUE_FALSE;
+            break;
+        case 'n':
+            _matchNull();
+            t = JsonToken.VALUE_NULL;
+            break;
+        case 't':
+            _matchTrue();
+            t = JsonToken.VALUE_TRUE;
+            break;
+        case '[':
+            t = JsonToken.START_ARRAY;
+            break;
+        case '{':
+            t = JsonToken.START_OBJECT;
+            break;
+        default:
+            t = _handleOddValue(i);
+            break;
+        }
+        _nextToken = t;
+        return nameToMatch.equals(name);
+    } /**
+     * Method for handling cases where first non-space character
+     * of an expected value token is not legal for standard JSON content.
+     */
+    protected JsonToken _handleOddValue(int i) throws IOException
+    {
+        // Most likely an error, unless we are to allow single-quote-strings
+        switch (i) {
+        case '\'':
+            /* Allow single quotes? Unlike with regular Strings, we'll eagerly parse
+             * contents; this so that there'sno need to store information on quote char used.
+             * Also, no separation to fast/slow parsing; we'll just do
+             * one regular (~= slowish) parsing, to keep code simple
+             */
+            if (isEnabled(Feature.ALLOW_SINGLE_QUOTES)) {
+                return _handleApos();
+            }
+            break;
+        case ']':
+            /* 28-Mar-2016: [core#116]: If Feature.ALLOW_MISSING_VALUES is enabled
+             *   we may allow "missing values", that is, encountering a trailing
+             *   comma or closing marker where value would be expected
+             */
+            if (!_parsingContext.inArray()) {
+                break;
+            }
+            // fall through
+        case ',':
+            if (isEnabled(Feature.ALLOW_MISSING_VALUES)) {
+                --_inputPtr;
+                return JsonToken.VALUE_NULL;
+            }
+            break;
+        case 'N':
+            _matchToken("NaN", 1);
+            if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
+                return resetAsNaN("NaN", Double.NaN);
+            }
+            _reportError("Non-standard token 'NaN': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
+            break;
+        case 'I':
+            _matchToken("Infinity", 1);
+            if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
+                return resetAsNaN("Infinity", Double.POSITIVE_INFINITY);
+            }
+            _reportError("Non-standard token 'Infinity': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
+            break;
+        case '+': // note: '-' is taken as number
+            if (_inputPtr >= _inputEnd) {
+                if (!_loadMore()) {
+                    _reportInvalidEOFInValue(JsonToken.VALUE_NUMBER_INT);
                 }
             }
+            return _handleInvalidNumberStart(_inputBuffer[_inputPtr++], false);
         }
-        return _skipWSOrEnd2();
-    }
-
-    private int _skipWSOrEnd2() throws IOException
+        // [core#77] Try to decode most likely token
+        if (Character.isJavaIdentifierStart(i)) {
+            _reportInvalidToken(""+((char) i), "('true', 'false' or 'null')");
+        }
+        // but if it doesn't look like a token:
+        _reportUnexpectedChar(i, "expected a valid value (number, String, array, object, 'true', 'false' or 'null')");
+        return null;
+    }private String _handleOddName2(int startPtr, int hash, int[] codes) throws IOException
     {
+        _textBuffer.resetWithShared(_inputBuffer, startPtr, (_inputPtr - startPtr));
+        char[] outBuf = _textBuffer.getCurrentSegment();
+        int outPtr = _textBuffer.getCurrentSegmentSize();
+        final int maxCode = codes.length;
+
         while (true) {
             if (_inputPtr >= _inputEnd) {
-                if (!_loadMore()) { // We ran out of input...
-                    return _eofAsNextChar();
+                if (!_loadMore()) { // acceptable for now (will error out later)
+                    break;
                 }
             }
-            int i = (int) _inputBuffer[_inputPtr++];
-            if (i > INT_SPACE) {
-                if (i == INT_SLASH) {
-                    _skipComment();
-                    continue;
-                }
-                if (i == INT_HASH) {
-                    if (_skipYAMLComment()) {
-                        continue;
-                    }
-                }
-                return i;
-            } else if (i != INT_SPACE) {
-                if (i == INT_LF) {
-                    ++_currInputRow;
-                    _currInputRowStart = _inputPtr;
-                } else if (i == INT_CR) {
-                    _skipCR();
-                } else if (i != INT_TAB) {
-                    _throwInvalidSpace(i);
+            char c = _inputBuffer[_inputPtr];
+            int i = (int) c;
+            if (i <= maxCode) {
+                if (codes[i] != 0) {
+                    break;
                 }
+            } else if (!Character.isJavaIdentifierPart(c)) {
+                break;
+            }
+            ++_inputPtr;
+            hash = (hash * CharsToNameCanonicalizer.HASH_MULT) + i;
+            // Ok, let's add char to output:
+            outBuf[outPtr++] = c;
+
+            // Need more room?
+            if (outPtr >= outBuf.length) {
+                outBuf = _textBuffer.finishCurrentSegment();
+                outPtr = 0;
             }
         }
-    }
+        _textBuffer.setCurrentLength(outPtr);
+        {
+            TextBuffer tb = _textBuffer;
+            char[] buf = tb.getTextBuffer();
+            int start = tb.getTextOffset();
+            int len = tb.size();
 
-    private void _skipComment() throws IOException
+            return _symbols.findSymbol(buf, start, len, hash);
+        }
+    } /**
+     * Method called when we see non-white space character other
+     * than double quote, when expecting a field name.
+     * In standard mode will just throw an expection; but
+     * in non-standard modes may be able to parse name.
+     */
+    protected String _handleOddName(int i) throws IOException
     {
-        if (!isEnabled(Feature.ALLOW_COMMENTS)) {
-            _reportUnexpectedChar('/', "maybe a (non-standard) comment? (not recognized as one since Feature 'ALLOW_COMMENTS' not enabled for parser)");
+        // [JACKSON-173]: allow single quotes
+        if (i == '\'' && isEnabled(Feature.ALLOW_SINGLE_QUOTES)) {
+            return _parseAposName();
         }
-        // First: check which comment (if either) it is:
-        if (_inputPtr >= _inputEnd && !_loadMore()) {
-            _reportInvalidEOF(" in a comment", null);
+        // [JACKSON-69]: allow unquoted names if feature enabled:
+        if (!isEnabled(Feature.ALLOW_UNQUOTED_FIELD_NAMES)) {
+            _reportUnexpectedChar(i, "was expecting double-quote to start field name");
         }
-        char c = _inputBuffer[_inputPtr++];
-        if (c == '/') {
-            _skipLine();
-        } else if (c == '*') {
-            _skipCComment();
+        final int[] codes = CharTypes.getInputCodeLatin1JsNames();
+        final int maxCode = codes.length;
+
+        // Also: first char must be a valid name char, but NOT be number
+        boolean firstOk;
+
+        if (i < maxCode) { // identifier, or a number ([Issue#102])
+            firstOk = (codes[i] == 0);
         } else {
-            _reportUnexpectedChar(c, "was expecting either '*' or '/' for a comment");
+            firstOk = Character.isJavaIdentifierPart((char) i);
+        }
+        if (!firstOk) {
+            _reportUnexpectedChar(i, "was expecting either valid name character (for unquoted name) or double-quote (for quoted) to start field name");
         }
-    }
+        int ptr = _inputPtr;
+        int hash = _hashSeed;
+        final int inputLen = _inputEnd;
 
-    private void _skipCComment() throws IOException
+        if (ptr < inputLen) {
+            do {
+                int ch = _inputBuffer[ptr];
+                if (ch < maxCode) {
+                    if (codes[ch] != 0) {
+                        int start = _inputPtr-1; // -1 to bring back first char
+                        _inputPtr = ptr;
+                        return _symbols.findSymbol(_inputBuffer, start, ptr - start, hash);
+                    }
+                } else if (!Character.isJavaIdentifierPart((char) ch)) {
+                    int start = _inputPtr-1; // -1 to bring back first char
+                    _inputPtr = ptr;
+                    return _symbols.findSymbol(_inputBuffer, start, ptr - start, hash);
+                }
+                hash = (hash * CharsToNameCanonicalizer.HASH_MULT) + ch;
+                ++ptr;
+            } while (ptr < inputLen);
+        }
+        int start = _inputPtr-1;
+        _inputPtr = ptr;
+        return _handleOddName2(start, hash, codes);
+    } /**
+     * Method called if expected numeric value (due to leading sign) does not
+     * look like a number
+     */
+    protected JsonToken _handleInvalidNumberStart(int ch, boolean negative) throws IOException
     {
-        // Ok: need the matching '*/'
-        while ((_inputPtr < _inputEnd) || _loadMore()) {
-            int i = (int) _inputBuffer[_inputPtr++];
-            if (i <= '*') {
-                if (i == '*') { // end?
-                    if ((_inputPtr >= _inputEnd) && !_loadMore()) {
+        if (ch == 'I') {
+            if (_inputPtr >= _inputEnd) {
+                if (!_loadMore()) {
+                    _reportInvalidEOFInValue(JsonToken.VALUE_NUMBER_INT);
+                }
+            }
+            ch = _inputBuffer[_inputPtr++];
+            if (ch == 'N') {
+                String match = negative ? "-INF" :"+INF";
+                _matchToken(match, 3);
+                if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
+                    return resetAsNaN(match, negative ? Double.NEGATIVE_INFINITY : Double.POSITIVE_INFINITY);
+                }
+                _reportError("Non-standard token '"+match+"': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
+            } else if (ch == 'n') {
+                String match = negative ? "-Infinity" :"+Infinity";
+                _matchToken(match, 3);
+                if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
+                    return resetAsNaN(match, negative ? Double.NEGATIVE_INFINITY : Double.POSITIVE_INFINITY);
+                }
+                _reportError("Non-standard token '"+match+"': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
+            }
+        }
+        reportUnexpectedNumberChar(ch, "expected digit (0-9) to follow minus sign, for valid numeric value");
+        return null;
+    }protected JsonToken _handleApos() throws IOException
+    {
+        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
+        int outPtr = _textBuffer.getCurrentSegmentSize();
+
+        while (true) {
+            if (_inputPtr >= _inputEnd) {
+                if (!_loadMore()) {
+                    _reportInvalidEOF(": was expecting closing quote for a string value",
+                            JsonToken.VALUE_STRING);
+                }
+            }
+            char c = _inputBuffer[_inputPtr++];
+            int i = (int) c;
+            if (i <= '\\') {
+                if (i == '\\') {
+                    /* Although chars outside of BMP are to be escaped as
+                     * an UTF-16 surrogate pair, does that affect decoding?
+                     * For now let's assume it does not.
+                     */
+                    c = _decodeEscaped();
+                } else if (i <= '\'') {
+                    if (i == '\'') {
                         break;
                     }
-                    if (_inputBuffer[_inputPtr] == INT_SLASH) {
-                        ++_inputPtr;
-                        return;
-                    }
-                    continue;
-                }
-                if (i < INT_SPACE) {
-                    if (i == INT_LF) {
-                        ++_currInputRow;
-                        _currInputRowStart = _inputPtr;
-                    } else if (i == INT_CR) {
-                        _skipCR();
-                    } else if (i != INT_TAB) {
-                        _throwInvalidSpace(i);
+                    if (i < INT_SPACE) {
+                        _throwUnquotedSpace(i, "string value");
                     }
                 }
             }
+            // Need more room?
+            if (outPtr >= outBuf.length) {
+                outBuf = _textBuffer.finishCurrentSegment();
+                outPtr = 0;
+            }
+            // Ok, let's add char to output:
+            outBuf[outPtr++] = c;
         }
-        _reportInvalidEOF(" in a comment", null);
-    }
+        _textBuffer.setCurrentLength(outPtr);
+        return JsonToken.VALUE_STRING;
+    }protected final String _getText2(JsonToken t) {
+        if (t == null) {
+            return null;
+        }
+        switch (t.id()) {
+        case ID_FIELD_NAME:
+            return _parsingContext.getCurrentName();
 
-    private boolean _skipYAMLComment() throws IOException
+        case ID_STRING:
+            // fall through
+        case ID_NUMBER_INT:
+        case ID_NUMBER_FLOAT:
+            return _textBuffer.contentsAsString();
+        default:
+            return t.asString();
+        }
+    }protected void _finishString2() throws IOException
     {
-        if (!isEnabled(Feature.ALLOW_YAML_COMMENTS)) {
-            return false;
+        char[] outBuf = _textBuffer.getCurrentSegment();
+        int outPtr = _textBuffer.getCurrentSegmentSize();
+        final int[] codes = _icLatin1;
+        final int maxCode = codes.length;
+
+        while (true) {
+            if (_inputPtr >= _inputEnd) {
+                if (!_loadMore()) {
+                    _reportInvalidEOF(": was expecting closing quote for a string value",
+                            JsonToken.VALUE_STRING);
+                }
+            }
+            char c = _inputBuffer[_inputPtr++];
+            int i = (int) c;
+            if (i < maxCode && codes[i] != 0) {
+                if (i == INT_QUOTE) {
+                    break;
+                } else if (i == INT_BACKSLASH) {
+                    /* Although chars outside of BMP are to be escaped as
+                     * an UTF-16 surrogate pair, does that affect decoding?
+                     * For now let's assume it does not.
+                     */
+                    c = _decodeEscaped();
+                } else if (i < INT_SPACE) {
+                    _throwUnquotedSpace(i, "string value");
+                } // anything else?
+            }
+            // Need more room?
+            if (outPtr >= outBuf.length) {
+                outBuf = _textBuffer.finishCurrentSegment();
+                outPtr = 0;
+            }
+            // Ok, let's add char to output:
+            outBuf[outPtr++] = c;
         }
-        _skipLine();
-        return true;
-    }
-
-    private void _skipLine() throws IOException
+        _textBuffer.setCurrentLength(outPtr);
+    }@Override
+    protected final void _finishString() throws IOException
     {
-        // Ok: need to find EOF or linefeed
-        while ((_inputPtr < _inputEnd) || _loadMore()) {
-            int i = (int) _inputBuffer[_inputPtr++];
-            if (i < INT_SPACE) {
-                if (i == INT_LF) {
-                    ++_currInputRow;
-                    _currInputRowStart = _inputPtr;
-                    break;
-                } else if (i == INT_CR) {
-                    _skipCR();
+        /* First: let's try to see if we have simple String value: one
+         * that does not cross input buffer boundary, and does not
+         * contain escape sequences.
+         */
+        int ptr = _inputPtr;
+        final int inputLen = _inputEnd;
+
+        if (ptr < inputLen) {
+            final int[] codes = _icLatin1;
+            final int maxCode = codes.length;
+
+            do {
+                int ch = _inputBuffer[ptr];
+                if (ch < maxCode && codes[ch] != 0) {
+                    if (ch == '"') {
+                        _textBuffer.resetWithShared(_inputBuffer, _inputPtr, (ptr-_inputPtr));
+                        _inputPtr = ptr+1;
+                        // Yes, we got it all
+                        return;
+                    }
                     break;
-                } else if (i != INT_TAB) {
-                    _throwInvalidSpace(i);
                 }
-            }
+                ++ptr;
+            } while (ptr < inputLen);
         }
-    }
 
-    @Override
+        /* Either ran out of input, or bumped into an escape
+         * sequence...
+         */
+        _textBuffer.resetWithCopy(_inputBuffer, _inputPtr, (ptr-_inputPtr));
+        _inputPtr = ptr;
+        _finishString2();
+    }@Override
     protected char _decodeEscaped() throws IOException
     {
         if (_inputPtr >= _inputEnd) {
@@ -2546,99 +2516,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
             value = (value << 4) | digit;
         }
         return (char) value;
-    }
-
-    private final void _matchTrue() throws IOException {
-        int ptr = _inputPtr;
-        if ((ptr + 3) < _inputEnd) {
-            final char[] b = _inputBuffer;
-            if (b[ptr] == 'r' && b[++ptr] == 'u' && b[++ptr] == 'e') {
-                char c = b[++ptr];
-                if (c < '0' || c == ']' || c == '}') { // expected/allowed chars
-                    _inputPtr = ptr;
-                    return;
-                }
-            }
-        }
-        // buffer boundary, or problem, offline
-        _matchToken("true", 1);
-    }
-
-    private final void _matchFalse() throws IOException {
-        int ptr = _inputPtr;
-        if ((ptr + 4) < _inputEnd) {
-            final char[] b = _inputBuffer;
-            if (b[ptr] == 'a' && b[++ptr] == 'l' && b[++ptr] == 's' && b[++ptr] == 'e') {
-                char c = b[++ptr];
-                if (c < '0' || c == ']' || c == '}') { // expected/allowed chars
-                    _inputPtr = ptr;
-                    return;
-                }
-            }
-        }
-        // buffer boundary, or problem, offline
-        _matchToken("false", 1);
-    }
-
-    private final void _matchNull() throws IOException {
-        int ptr = _inputPtr;
-        if ((ptr + 3) < _inputEnd) {
-            final char[] b = _inputBuffer;
-            if (b[ptr] == 'u' && b[++ptr] == 'l' && b[++ptr] == 'l') {
-                char c = b[++ptr];
-                if (c < '0' || c == ']' || c == '}') { // expected/allowed chars
-                    _inputPtr = ptr;
-                    return;
-                }
-            }
-        }
-        // buffer boundary, or problem, offline
-        _matchToken("null", 1);
-    }
-
-    /**
-     * Helper method for checking whether input matches expected token
-     */
-    protected final void _matchToken(String matchStr, int i) throws IOException
-    {
-        final int len = matchStr.length();
-
-        do {
-            if (_inputPtr >= _inputEnd) {
-                if (!_loadMore()) {
-                    _reportInvalidToken(matchStr.substring(0, i));
-                }
-            }
-            if (_inputBuffer[_inputPtr] != matchStr.charAt(i)) {
-                _reportInvalidToken(matchStr.substring(0, i));
-            }
-            ++_inputPtr;
-        } while (++i < len);
-
-        // but let's also ensure we either get EOF, or non-alphanum char...
-        if (_inputPtr >= _inputEnd) {
-            if (!_loadMore()) {
-                return;
-            }
-        }
-        char c = _inputBuffer[_inputPtr];
-        if (c < '0' || c == ']' || c == '}') { // expected/allowed chars
-            return;
-        }
-        // if Java letter, it's a problem tho
-        if (Character.isJavaIdentifierPart(c)) {
-            _reportInvalidToken(matchStr.substring(0, i));
-        }
-        return;
-    }
-
-    /*
-    /**********************************************************
-    /* Binary access
-    /**********************************************************
-     */
-
-    /**
+    } /**
      * Efficient handling for incremental parsing of base64-encoded
      * textual content.
      */
@@ -2749,91 +2627,7 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
             decodedData = (decodedData << 6) | bits;
             builder.appendThreeBytes(decodedData);
         }
-    }
-
-    /*
-    /**********************************************************
-    /* Internal methods, location updating (refactored in 2.7)
-    /**********************************************************
-     */
-
-    @Override
-    public JsonLocation getTokenLocation()
-    {
-        if (_currToken == JsonToken.FIELD_NAME) {
-            long total = _currInputProcessed + (_nameStartOffset-1);
-            return new JsonLocation(_getSourceReference(),
-                    -1L, total, _nameStartRow, _nameStartCol);
-        }
-        return new JsonLocation(_getSourceReference(),
-                -1L, _tokenInputTotal-1, _tokenInputRow, _tokenInputCol);
-    }
-
-    @Override
-    public JsonLocation getCurrentLocation() {
-        int col = _inputPtr - _currInputRowStart + 1; // 1-based
-        return new JsonLocation(_getSourceReference(),
-                -1L, _currInputProcessed + _inputPtr,
-                _currInputRow, col);
-    }
-
-    // @since 2.7
-    private final void _updateLocation()
-    {
-        int ptr = _inputPtr;
-        _tokenInputTotal = _currInputProcessed + ptr;
-        _tokenInputRow = _currInputRow;
-        _tokenInputCol = ptr - _currInputRowStart;
-    }
-
-    // @since 2.7
-    private final void _updateNameLocation()
-    {
-        int ptr = _inputPtr;
-        _nameStartOffset = ptr;
-        _nameStartRow = _currInputRow;
-        _nameStartCol = ptr - _currInputRowStart;
-    }
-
-    /*
-    /**********************************************************
-    /* Error reporting
-    /**********************************************************
-     */
-
-    protected void _reportInvalidToken(String matchedPart) throws IOException {
-        _reportInvalidToken(matchedPart, "'null', 'true', 'false' or NaN");
-    }
-
-    protected void _reportInvalidToken(String matchedPart, String msg) throws IOException
-    {
-        /* Let's just try to find what appears to be the token, using
-         * regular Java identifier character rules. It's just a heuristic,
-         * nothing fancy here.
-         */
-        StringBuilder sb = new StringBuilder(matchedPart);
-        while ((_inputPtr < _inputEnd) || _loadMore()) {
-            char c = _inputBuffer[_inputPtr];
-            if (!Character.isJavaIdentifierPart(c)) {
-                break;
-            }
-            ++_inputPtr;
-            sb.append(c);
-            if (sb.length() >= MAX_ERROR_TOKEN_LENGTH) {
-                sb.append("...");
-                break;
-            }
-        }
-        _reportError("Unrecognized token '%s': was expecting %s", sb, msg);
-    }
-
-    /*
-    /**********************************************************
-    /* Internal methods, other
-    /**********************************************************
-     */
-
-    private void _closeScope(int i) throws JsonParseException {
+    }private void _closeScope(int i) throws JsonParseException {
         if (i == INT_RBRACKET) {
             _updateLocation();
             if (!_parsingContext.inArray()) {
@@ -2850,5 +2644,55 @@ public class ReaderBasedJsonParser // final in 2.3, earlier
             _parsingContext = _parsingContext.clearAndGetParent();
             _currToken = JsonToken.END_OBJECT;
         }
-    }
-}
+    }@Override
+    protected void _closeInput() throws IOException {
+        /* 25-Nov-2008, tatus: As per [JACKSON-16] we are not to call close()
+         *   on the underlying Reader, unless we "own" it, or auto-closing
+         *   feature is enabled.
+         *   One downside is that when using our optimized
+         *   Reader (granted, we only do that for UTF-32...) this
+         *   means that buffer recycling won't work correctly.
+         */
+        if (_reader != null) {
+            if (_ioContext.isResourceManaged() || isEnabled(Feature.AUTO_CLOSE_SOURCE)) {
+                _reader.close();
+            }
+            _reader = null;
+        }
+    } /**
+     * Method called when caller wants to provide input buffer directly,
+     * and it may or may not be recyclable use standard recycle context.
+     *
+     * @since 2.4
+     */
+    public ReaderBasedJsonParser(IOContext ctxt, int features, Reader r,
+            ObjectCodec codec, CharsToNameCanonicalizer st,
+            char[] inputBuffer, int start, int end,
+            boolean bufferRecyclable)
+    {
+        super(ctxt, features);
+        _reader = r;
+        _inputBuffer = inputBuffer;
+        _inputPtr = start;
+        _inputEnd = end;
+        _objectCodec = codec;
+        _symbols = st;
+        _hashSeed = st.hashSeed();
+        _bufferRecyclable = bufferRecyclable;
+    } /**
+     * Method called when input comes as a {@link java.io.Reader}, and buffer allocation
+     * can be done using default mechanism.
+     */
+    public ReaderBasedJsonParser(IOContext ctxt, int features, Reader r,
+        ObjectCodec codec, CharsToNameCanonicalizer st)
+    {
+        super(ctxt, features);
+        _reader = r;
+        _inputBuffer = ctxt.allocTokenBuffer();
+        _inputPtr = 0;
+        _inputEnd = 0;
+        _objectCodec = codec;
+        _symbols = st;
+        _hashSeed = st.hashSeed();
+        _bufferRecyclable = true;
+    }}
diff --git a/src/main/java/com/fasterxml/jackson/core/json/UTF8DataInputJsonParser.java b/src/main/java/com/fasterxml/jackson/core/io/UTF8DataInputJsonParser.java
similarity index 95%
rename from src/main/java/com/fasterxml/jackson/core/json/UTF8DataInputJsonParser.java
rename to src/main/java/com/fasterxml/jackson/core/io/UTF8DataInputJsonParser.java
index 7881b48c..ab6cc43c 100644
--- a/src/main/java/com/fasterxml/jackson/core/json/UTF8DataInputJsonParser.java
+++ b/src/main/java/com/fasterxml/jackson/core/io/UTF8DataInputJsonParser.java
@@ -1,12 +1,10 @@
-package com.fasterxml.jackson.core.json;
+package com.fasterxml.jackson.core.io;
 
 import java.io.*;
 import java.util.Arrays;
 
 import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.core.base.ParserBase;
-import com.fasterxml.jackson.core.io.CharTypes;
-import com.fasterxml.jackson.core.io.IOContext;
 import com.fasterxml.jackson.core.sym.ByteQuadsCanonicalizer;
 import com.fasterxml.jackson.core.util.*;
 
@@ -105,484 +103,443 @@ public class UTF8DataInputJsonParser
     /**********************************************************
      */
 
-    public UTF8DataInputJsonParser(IOContext ctxt, int features, DataInput inputData,
-            ObjectCodec codec, ByteQuadsCanonicalizer sym,
-            int firstByte)
-    {
-        super(ctxt, features);
-        _objectCodec = codec;
-        _symbols = sym;
-        _inputData = inputData;
-        _nextByte = firstByte;
-    }
+    /*
+    /**********************************************************
+    /* Overrides for life-cycle
+    /**********************************************************
+     */
 
-    @Override
-    public ObjectCodec getCodec() {
-        return _objectCodec;
-    }
+    /*
+    /**********************************************************
+    /* Overrides, low-level reading
+    /**********************************************************
+     */
 
-    @Override
-    public void setCodec(ObjectCodec c) {
-        _objectCodec = c;
-    }
+    /*
+    /**********************************************************
+    /* Public API, data access
+    /**********************************************************
+     */
 
     /*
     /**********************************************************
-    /* Overrides for life-cycle
+    /* Public API, traversal, basic
     /**********************************************************
      */
 
-    @Override
-    public int releaseBuffered(OutputStream out) throws IOException {
-        return 0;
-    }
+    /*
+    /**********************************************************
+    /* Public API, traversal, nextXxxValue/nextFieldName
+    /**********************************************************
+     */
 
-    @Override
-    public Object getInputSource() {
-        return _inputData;
-    }
+    // Can not implement without look-ahead...
+//    public boolean nextFieldName(SerializableString str) throws IOException
 
     /*
     /**********************************************************
-    /* Overrides, low-level reading
+    /* Internal methods, number parsing
     /**********************************************************
      */
 
-    @Override
-    protected void _closeInput() throws IOException { }
+    /*
+    /**********************************************************
+    /* Internal methods, secondary parsing
+    /**********************************************************
+     */
+    
+    /*
+    /**********************************************************
+    /* Internal methods, symbol (name) handling
+    /**********************************************************
+     */
 
-    /**
-     * Method called to release internal buffers owned by the base
-     * reader. This may be called along with {@link #_closeInput} (for
-     * example, when explicitly closing this reader instance), or
-     * separately (if need be).
+    /*
+    /**********************************************************
+    /* Internal methods, String value parsing
+    /**********************************************************
      */
-    @Override
-    protected void _releaseBuffers() throws IOException
-    {
-        super._releaseBuffers();
-        // Merge found symbols, if any:
-        _symbols.release();
-    }
 
     /*
     /**********************************************************
-    /* Public API, data access
+    /* Internal methods, ws skipping, escape/unescape
     /**********************************************************
      */
 
-    @Override
-    public String getText() throws IOException
-    {
-        if (_currToken == JsonToken.VALUE_STRING) {
-            if (_tokenIncomplete) {
-                _tokenIncomplete = false;
-                return _finishAndReturnString(); // only strings can be incomplete
-            }
-            return _textBuffer.contentsAsString();
-        }
-        return _getText2(_currToken);
-    }
+    /*
+    /**********************************************************
+    /* Internal methods,UTF8 decoding
+    /**********************************************************
+     */
 
-    @Override
-    public int getText(Writer writer) throws IOException
-    {
-        JsonToken t = _currToken;
-        if (t == JsonToken.VALUE_STRING) {
-            if (_tokenIncomplete) {
-                _tokenIncomplete = false;
-                _finishString(); // only strings can be incomplete
-            }
-            return _textBuffer.contentsToWriter(writer);
-        }
-        if (t == JsonToken.FIELD_NAME) {
-            String n = _parsingContext.getCurrentName();
-            writer.write(n);
-            return n.length();
-        }
-        if (t != null) {
-            if (t.isNumeric()) {
-                return _textBuffer.contentsToWriter(writer);
-            }
-            char[] ch = t.asCharArray();
-            writer.write(ch);
-            return ch.length;
-        }
-        return 0;
-    }
+    /*
+    /**********************************************************
+    /* Internal methods, error reporting
+    /**********************************************************
+     */
 
-    // // // Let's override default impls for improved performance
-    @Override
-    public String getValueAsString() throws IOException
-    {
-        if (_currToken == JsonToken.VALUE_STRING) {
-            if (_tokenIncomplete) {
-                _tokenIncomplete = false;
-                return _finishAndReturnString(); // only strings can be incomplete
-            }
-            return _textBuffer.contentsAsString();
-        }
-        if (_currToken == JsonToken.FIELD_NAME) {
-            return getCurrentName();
-        }
-        return super.getValueAsString(null);
-    }
+    /*
+    /**********************************************************
+    /* Internal methods, binary access
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Improved location updating (refactored in 2.7)
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Internal methods, other
+    /**********************************************************
+     */
 
     @Override
-    public String getValueAsString(String defValue) throws IOException
+    public void setCodec(ObjectCodec c) {
+        _objectCodec = c;
+    }@Override
+    public int releaseBuffered(OutputStream out) throws IOException {
+        return 0;
+    }@Override
+    public int readBinaryValue(Base64Variant b64variant, OutputStream out) throws IOException
     {
-        if (_currToken == JsonToken.VALUE_STRING) {
-            if (_tokenIncomplete) {
-                _tokenIncomplete = false;
-                return _finishAndReturnString(); // only strings can be incomplete
-            }
-            return _textBuffer.contentsAsString();
+        // if we have already read the token, just use whatever we may have
+        if (!_tokenIncomplete || _currToken != JsonToken.VALUE_STRING) {
+            byte[] b = getBinaryValue(b64variant);
+            out.write(b);
+            return b.length;
         }
-        if (_currToken == JsonToken.FIELD_NAME) {
-            return getCurrentName();
+        // otherwise do "real" incremental parsing...
+        byte[] buf = _ioContext.allocBase64Buffer();
+        try {
+            return _readBinary(b64variant, out, buf);
+        } finally {
+            _ioContext.releaseBase64Buffer(buf);
         }
-        return super.getValueAsString(defValue);
-    }
-
-    @Override
-    public int getValueAsInt() throws IOException
+    }private final String parseName(int q1, int ch, int lastQuadBytes) throws IOException {
+        return parseEscapedName(_quadBuffer, 0, q1, ch, lastQuadBytes);
+    }private final String parseName(int q1, int q2, int ch, int lastQuadBytes) throws IOException {
+        _quadBuffer[0] = q1;
+        return parseEscapedName(_quadBuffer, 1, q2, ch, lastQuadBytes);
+    }private final String parseName(int q1, int q2, int q3, int ch, int lastQuadBytes) throws IOException {
+        _quadBuffer[0] = q1;
+        _quadBuffer[1] = q2;
+        return parseEscapedName(_quadBuffer, 2, q3, ch, lastQuadBytes);
+    } /**
+     * Slower parsing method which is generally branched to when
+     * an escape sequence is detected (or alternatively for long
+     * names, one crossing input buffer boundary).
+     * Needs to be able to handle more exceptional cases, gets slower,
+     * and hance is offlined to a separate method.
+     */
+    protected final String parseEscapedName(int[] quads, int qlen, int currQuad, int ch,
+            int currQuadBytes) throws IOException
     {
-        JsonToken t = _currToken;
-        if ((t == JsonToken.VALUE_NUMBER_INT) || (t == JsonToken.VALUE_NUMBER_FLOAT)) {
-            // inlined 'getIntValue()'
-            if ((_numTypesValid & NR_INT) == 0) {
-                if (_numTypesValid == NR_UNKNOWN) {
-                    return _parseIntValue();
-                }
-                if ((_numTypesValid & NR_INT) == 0) {
-                    convertNumberToInt();
-                }
-            }
-            return _numberInt;
-        }
-        return super.getValueAsInt(0);
-    }
+        /* 25-Nov-2008, tatu: This may seem weird, but here we do not want to worry about
+         *   UTF-8 decoding yet. Rather, we'll assume that part is ok (if not it will get
+         *   caught later on), and just handle quotes and backslashes here.
+         */
+        final int[] codes = _icLatin1;
 
-    @Override
-    public int getValueAsInt(int defValue) throws IOException
-    {
-        JsonToken t = _currToken;
-        if ((t == JsonToken.VALUE_NUMBER_INT) || (t == JsonToken.VALUE_NUMBER_FLOAT)) {
-            // inlined 'getIntValue()'
-            if ((_numTypesValid & NR_INT) == 0) {
-                if (_numTypesValid == NR_UNKNOWN) {
-                    return _parseIntValue();
+        while (true) {
+            if (codes[ch] != 0) {
+                if (ch == INT_QUOTE) { // we are done
+                    break;
                 }
-                if ((_numTypesValid & NR_INT) == 0) {
-                    convertNumberToInt();
+                // Unquoted white space?
+                if (ch != INT_BACKSLASH) {
+                    // As per [JACKSON-208], call can now return:
+                    _throwUnquotedSpace(ch, "name");
+                } else {
+                    // Nope, escape sequence
+                    ch = _decodeEscaped();
                 }
-            }
-            return _numberInt;
-        }
-        return super.getValueAsInt(defValue);
-    }
-    
-    protected final String _getText2(JsonToken t)
-    {
-        if (t == null) {
-            return null;
-        }
-        switch (t.id()) {
-        case ID_FIELD_NAME:
-            return _parsingContext.getCurrentName();
-
-        case ID_STRING:
-            // fall through
-        case ID_NUMBER_INT:
-        case ID_NUMBER_FLOAT:
-            return _textBuffer.contentsAsString();
-        default:
-        	return t.asString();
-        }
-    }
-
-    @Override
-    public char[] getTextCharacters() throws IOException
-    {
-        if (_currToken != null) { // null only before/after document
-            switch (_currToken.id()) {
-                
-            case ID_FIELD_NAME:
-                if (!_nameCopied) {
-                    String name = _parsingContext.getCurrentName();
-                    int nameLen = name.length();
-                    if (_nameCopyBuffer == null) {
-                        _nameCopyBuffer = _ioContext.allocNameCopyBuffer(nameLen);
-                    } else if (_nameCopyBuffer.length < nameLen) {
-                        _nameCopyBuffer = new char[nameLen];
+                /* Oh crap. May need to UTF-8 (re-)encode it, if it's
+                 * beyond 7-bit ascii. Gets pretty messy.
+                 * If this happens often, may want to use different name
+                 * canonicalization to avoid these hits.
+                 */
+                if (ch > 127) {
+                    // Ok, we'll need room for first byte right away
+                    if (currQuadBytes >= 4) {
+                        if (qlen >= quads.length) {
+                            _quadBuffer = quads = _growArrayBy(quads, quads.length);
+                        }
+                        quads[qlen++] = currQuad;
+                        currQuad = 0;
+                        currQuadBytes = 0;
                     }
-                    name.getChars(0, nameLen, _nameCopyBuffer, 0);
-                    _nameCopied = true;
+                    if (ch < 0x800) { // 2-byte
+                        currQuad = (currQuad << 8) | (0xc0 | (ch >> 6));
+                        ++currQuadBytes;
+                        // Second byte gets output below:
+                    } else { // 3 bytes; no need to worry about surrogates here
+                        currQuad = (currQuad << 8) | (0xe0 | (ch >> 12));
+                        ++currQuadBytes;
+                        // need room for middle byte?
+                        if (currQuadBytes >= 4) {
+                            if (qlen >= quads.length) {
+                                _quadBuffer = quads = _growArrayBy(quads, quads.length);
+                            }
+                            quads[qlen++] = currQuad;
+                            currQuad = 0;
+                            currQuadBytes = 0;
+                        }
+                        currQuad = (currQuad << 8) | (0x80 | ((ch >> 6) & 0x3f));
+                        ++currQuadBytes;
+                    }
+                    // And same last byte in both cases, gets output below:
+                    ch = 0x80 | (ch & 0x3f);
                 }
-                return _nameCopyBuffer;
-    
-            case ID_STRING:
-                if (_tokenIncomplete) {
-                    _tokenIncomplete = false;
-                    _finishString(); // only strings can be incomplete
+            }
+            // Ok, we have one more byte to add at any rate:
+            if (currQuadBytes < 4) {
+                ++currQuadBytes;
+                currQuad = (currQuad << 8) | ch;
+            } else {
+                if (qlen >= quads.length) {
+                    _quadBuffer = quads = _growArrayBy(quads, quads.length);
                 }
-                // fall through
-            case ID_NUMBER_INT:
-            case ID_NUMBER_FLOAT:
-                return _textBuffer.getTextBuffer();
-                
-            default:
-                return _currToken.asCharArray();
+                quads[qlen++] = currQuad;
+                currQuad = ch;
+                currQuadBytes = 1;
             }
+            ch = _inputData.readUnsignedByte();
         }
-        return null;
-    }
 
-    @Override
-    public int getTextLength() throws IOException
-    {
-        if (_currToken == JsonToken.VALUE_STRING) {
-            if (_tokenIncomplete) {
-                _tokenIncomplete = false;
-                _finishString(); // only strings can be incomplete
-            }
-            return _textBuffer.size();
-        }
-        if (_currToken == JsonToken.FIELD_NAME) {
-            return _parsingContext.getCurrentName().length();
-        }
-        if (_currToken != null) { // null only before/after document
-            if (_currToken.isNumeric()) {
-                return _textBuffer.size();
+        if (currQuadBytes > 0) {
+            if (qlen >= quads.length) {
+                _quadBuffer = quads = _growArrayBy(quads, quads.length);
             }
-            return _currToken.asCharArray().length;
+            quads[qlen++] = pad(currQuad, currQuadBytes);
         }
-        return 0;
-    }
-
-    @Override
-    public int getTextOffset() throws IOException
-    {
-        // Most have offset of 0, only some may have other values:
-        if (_currToken != null) {
-            switch (_currToken.id()) {
-            case ID_FIELD_NAME:
-                return 0;
-            case ID_STRING:
-                if (_tokenIncomplete) {
-                    _tokenIncomplete = false;
-                    _finishString(); // only strings can be incomplete
-                }
-                // fall through
-            case ID_NUMBER_INT:
-            case ID_NUMBER_FLOAT:
-                return _textBuffer.getTextOffset();
-            default:
-            }
+        String name = _symbols.findName(quads, qlen);
+        if (name == null) {
+            name = addName(quads, qlen, currQuadBytes);
         }
-        return 0;
-    }
-    
+        return name;
+    } /**
+     * Helper method needed to fix [Issue#148], masking of 0x00 character
+     */
+    private final static int pad(int q, int bytes) {
+        return (bytes == 4) ? q : (q | (-1 << (bytes << 3)));
+    } /**
+     * @return Next token from the stream, if any found, or null
+     *   to indicate end-of-input
+     */
     @Override
-    public byte[] getBinaryValue(Base64Variant b64variant) throws IOException
+    public JsonToken nextToken() throws IOException
     {
-        if (_currToken != JsonToken.VALUE_STRING &&
-                (_currToken != JsonToken.VALUE_EMBEDDED_OBJECT || _binaryValue == null)) {
-            _reportError("Current token ("+_currToken+") not VALUE_STRING or VALUE_EMBEDDED_OBJECT, can not access as binary");
-        }
-        /* To ensure that we won't see inconsistent data, better clear up
-         * state...
+        /* First: field names are special -- we will always tokenize
+         * (part of) value along with field name to simplify
+         * state handling. If so, can and need to use secondary token:
          */
-        if (_tokenIncomplete) {
-            try {
-                _binaryValue = _decodeBase64(b64variant);
-            } catch (IllegalArgumentException iae) {
-                throw _constructError("Failed to decode VALUE_STRING as base64 ("+b64variant+"): "+iae.getMessage());
-            }
-            /* let's clear incomplete only now; allows for accessing other
-             * textual content in error cases
-             */
-            _tokenIncomplete = false;
-        } else { // may actually require conversion...
-            if (_binaryValue == null) {
-                @SuppressWarnings("resource")
-                ByteArrayBuilder builder = _getByteArrayBuilder();
-                _decodeBase64(getText(), builder, b64variant);
-                _binaryValue = builder.toByteArray();
-            }
+        if (_currToken == JsonToken.FIELD_NAME) {
+            return _nextAfterName();
         }
-        return _binaryValue;
-    }
-
-    @Override
-    public int readBinaryValue(Base64Variant b64variant, OutputStream out) throws IOException
-    {
-        // if we have already read the token, just use whatever we may have
-        if (!_tokenIncomplete || _currToken != JsonToken.VALUE_STRING) {
-            byte[] b = getBinaryValue(b64variant);
-            out.write(b);
-            return b.length;
+        // But if we didn't already have a name, and (partially?) decode number,
+        // need to ensure no numeric information is leaked
+        _numTypesValid = NR_UNKNOWN;
+        if (_tokenIncomplete) {
+            _skipString(); // only strings can be partial
         }
-        // otherwise do "real" incremental parsing...
-        byte[] buf = _ioContext.allocBase64Buffer();
-        try {
-            return _readBinary(b64variant, out, buf);
-        } finally {
-            _ioContext.releaseBase64Buffer(buf);
+        int i = _skipWSOrEnd();
+        if (i < 0) { // end-of-input
+            // Close/release things like input source, symbol table and recyclable buffers
+            close();
+            return (_currToken = null);
         }
-    }
+        // clear any data retained so far
+        _binaryValue = null;
+        _tokenInputRow = _currInputRow;
 
-    protected int _readBinary(Base64Variant b64variant, OutputStream out,
-                              byte[] buffer) throws IOException
-    {
-        int outputPtr = 0;
-        final int outputEnd = buffer.length - 3;
-        int outputCount = 0;
+        // Closing scope?
+        if (i == INT_RBRACKET || i == INT_RCURLY) {
+            _closeScope(i);
+            return _currToken;
+        }
 
-        while (true) {
-            // first, we'll skip preceding white space, if any
-            int ch;
-            do {
-                ch = _inputData.readUnsignedByte();
-            } while (ch <= INT_SPACE);
-            int bits = b64variant.decodeBase64Char(ch);
-            if (bits < 0) { // reached the end, fair and square?
-                if (ch == INT_QUOTE) {
-                    break;
-                }
-                bits = _decodeBase64Escape(b64variant, ch, 0);
-                if (bits < 0) { // white space to skip
-                    continue;
-                }
+        // Nope: do we then expect a comma?
+        if (_parsingContext.expectComma()) {
+            if (i != INT_COMMA) {
+                _reportUnexpectedChar(i, "was expecting comma to separate "+_parsingContext.typeDesc()+" entries");
             }
+            i = _skipWS();
 
-            // enough room? If not, flush
-            if (outputPtr > outputEnd) {
-                outputCount += outputPtr;
-                out.write(buffer, 0, outputPtr);
-                outputPtr = 0;
+            // Was that a trailing comma?
+            if (Feature.ALLOW_TRAILING_COMMA.enabledIn(_features)) {
+                if (i == INT_RBRACKET || i == INT_RCURLY) {
+                    _closeScope(i);
+                    return _currToken;
+                }
             }
+        }
 
-            int decodedData = bits;
+        /* And should we now have a name? Always true for
+         * Object contexts, since the intermediate 'expect-value'
+         * state is never retained.
+         */
+        if (!_parsingContext.inObject()) {
+            return _nextTokenNotInObject(i);
+        }
+        // So first parse the field name itself:
+        String n = _parseName(i);
+        _parsingContext.setCurrentName(n);
+        _currToken = JsonToken.FIELD_NAME;
 
-            // then second base64 char; can't get padding yet, nor ws
-            ch = _inputData.readUnsignedByte();
-            bits = b64variant.decodeBase64Char(ch);
-            if (bits < 0) {
-                bits = _decodeBase64Escape(b64variant, ch, 1);
-            }
-            decodedData = (decodedData << 6) | bits;
+        i = _skipColon();
 
-            // third base64 char; can be padding, but not ws
-            ch = _inputData.readUnsignedByte();
-            bits = b64variant.decodeBase64Char(ch);
+        // Ok: we must have a value... what is it? Strings are very common, check first:
+        if (i == INT_QUOTE) {
+            _tokenIncomplete = true;
+            _nextToken = JsonToken.VALUE_STRING;
+            return _currToken;
+        }
+        JsonToken t;
 
-            // First branch: can get padding (-> 1 byte)
-            if (bits < 0) {
-                if (bits != Base64Variant.BASE64_VALUE_PADDING) {
-                    // could also just be 'missing'  padding
-                    if (ch == '"' && !b64variant.usesPadding()) {
-                        decodedData >>= 4;
-                        buffer[outputPtr++] = (byte) decodedData;
-                        break;
-                    }
-                    bits = _decodeBase64Escape(b64variant, ch, 2);
-                }
-                if (bits == Base64Variant.BASE64_VALUE_PADDING) {
-                    // Ok, must get padding
-                    ch = _inputData.readUnsignedByte();
-                    if (!b64variant.usesPaddingChar(ch)) {
-                        throw reportInvalidBase64Char(b64variant, ch, 3, "expected padding character '"+b64variant.getPaddingChar()+"'");
-                    }
-                    // Got 12 bits, only need 8, need to shift
-                    decodedData >>= 4;
-                    buffer[outputPtr++] = (byte) decodedData;
-                    continue;
+        switch (i) {
+        case '-':
+            t = _parseNegNumber();
+            break;
+
+            /* Should we have separate handling for plus? Although
+             * it is not allowed per se, it may be erroneously used,
+             * and could be indicate by a more specific error message.
+             */
+        case '0':
+        case '1':
+        case '2':
+        case '3':
+        case '4':
+        case '5':
+        case '6':
+        case '7':
+        case '8':
+        case '9':
+            t = _parsePosNumber(i);
+            break;
+        case 'f':
+            _matchToken("false", 1);
+             t = JsonToken.VALUE_FALSE;
+            break;
+        case 'n':
+            _matchToken("null", 1);
+            t = JsonToken.VALUE_NULL;
+            break;
+        case 't':
+            _matchToken("true", 1);
+            t = JsonToken.VALUE_TRUE;
+            break;
+        case '[':
+            t = JsonToken.START_ARRAY;
+            break;
+        case '{':
+            t = JsonToken.START_OBJECT;
+            break;
+
+        default:
+            t = _handleUnexpectedValue(i);
+        }
+        _nextToken = t;
+        return _currToken;
+    }@Override
+    public String nextTextValue() throws IOException
+    {
+        // two distinct cases; either got name and we know next type, or 'other'
+        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
+            _nameCopied = false;
+            JsonToken t = _nextToken;
+            _nextToken = null;
+            _currToken = t;
+            if (t == JsonToken.VALUE_STRING) {
+                if (_tokenIncomplete) {
+                    _tokenIncomplete = false;
+                    return _finishAndReturnString();
                 }
+                return _textBuffer.contentsAsString();
             }
-            // Nope, 2 or 3 bytes
-            decodedData = (decodedData << 6) | bits;
-            // fourth and last base64 char; can be padding, but not ws
-            ch = _inputData.readUnsignedByte();
-            bits = b64variant.decodeBase64Char(ch);
-            if (bits < 0) {
-                if (bits != Base64Variant.BASE64_VALUE_PADDING) {
-                    // could also just be 'missing'  padding
-                    if (ch == '"' && !b64variant.usesPadding()) {
-                        decodedData >>= 2;
-                        buffer[outputPtr++] = (byte) (decodedData >> 8);
-                        buffer[outputPtr++] = (byte) decodedData;
-                        break;
-                    }
-                    bits = _decodeBase64Escape(b64variant, ch, 3);
-                }
-                if (bits == Base64Variant.BASE64_VALUE_PADDING) {
-                    /* With padding we only get 2 bytes; but we have
-                     * to shift it a bit so it is identical to triplet
-                     * case with partial output.
-                     * 3 chars gives 3x6 == 18 bits, of which 2 are
-                     * dummies, need to discard:
-                     */
-                    decodedData >>= 2;
-                    buffer[outputPtr++] = (byte) (decodedData >> 8);
-                    buffer[outputPtr++] = (byte) decodedData;
-                    continue;
-                }
+            if (t == JsonToken.START_ARRAY) {
+                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            } else if (t == JsonToken.START_OBJECT) {
+                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
             }
-            // otherwise, our triplet is now complete
-            decodedData = (decodedData << 6) | bits;
-            buffer[outputPtr++] = (byte) (decodedData >> 16);
-            buffer[outputPtr++] = (byte) (decodedData >> 8);
-            buffer[outputPtr++] = (byte) decodedData;
+            return null;
         }
-        _tokenIncomplete = false;
-        if (outputPtr > 0) {
-            outputCount += outputPtr;
-            out.write(buffer, 0, outputPtr);
+        return (nextToken() == JsonToken.VALUE_STRING) ? getText() : null;
+    }@Override
+    public long nextLongValue(long defaultValue) throws IOException
+    {
+        // two distinct cases; either got name and we know next type, or 'other'
+        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
+            _nameCopied = false;
+            JsonToken t = _nextToken;
+            _nextToken = null;
+            _currToken = t;
+            if (t == JsonToken.VALUE_NUMBER_INT) {
+                return getLongValue();
+            }
+            if (t == JsonToken.START_ARRAY) {
+                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            } else if (t == JsonToken.START_OBJECT) {
+                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            }
+            return defaultValue;
         }
-        return outputCount;
-    }
-
-    /*
-    /**********************************************************
-    /* Public API, traversal, basic
-    /**********************************************************
-     */
-
-    /**
-     * @return Next token from the stream, if any found, or null
-     *   to indicate end-of-input
-     */
-    @Override
-    public JsonToken nextToken() throws IOException
+        return (nextToken() == JsonToken.VALUE_NUMBER_INT) ? getLongValue() : defaultValue;
+    }@Override
+    public int nextIntValue(int defaultValue) throws IOException
     {
-        /* First: field names are special -- we will always tokenize
-         * (part of) value along with field name to simplify
-         * state handling. If so, can and need to use secondary token:
-         */
-        if (_currToken == JsonToken.FIELD_NAME) {
-            return _nextAfterName();
+        // two distinct cases; either got name and we know next type, or 'other'
+        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
+            _nameCopied = false;
+            JsonToken t = _nextToken;
+            _nextToken = null;
+            _currToken = t;
+            if (t == JsonToken.VALUE_NUMBER_INT) {
+                return getIntValue();
+            }
+            if (t == JsonToken.START_ARRAY) {
+                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            } else if (t == JsonToken.START_OBJECT) {
+                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            }
+            return defaultValue;
         }
-        // But if we didn't already have a name, and (partially?) decode number,
-        // need to ensure no numeric information is leaked
+        return (nextToken() == JsonToken.VALUE_NUMBER_INT) ? getIntValue() : defaultValue;
+    }@Override
+    public String nextFieldName() throws IOException
+    {
+        // // // Note: this is almost a verbatim copy of nextToken()
+
         _numTypesValid = NR_UNKNOWN;
-        if (_tokenIncomplete) {
-            _skipString(); // only strings can be partial
+        if (_currToken == JsonToken.FIELD_NAME) {
+            _nextAfterName();
+            return null;
         }
-        int i = _skipWSOrEnd();
-        if (i < 0) { // end-of-input
-            // Close/release things like input source, symbol table and recyclable buffers
-            close();
-            return (_currToken = null);
+        if (_tokenIncomplete) {
+            _skipString();
         }
-        // clear any data retained so far
+        int i = _skipWS();
         _binaryValue = null;
         _tokenInputRow = _currInputRow;
 
-        // Closing scope?
-        if (i == INT_RBRACKET || i == INT_RCURLY) {
-            _closeScope(i);
-            return _currToken;
+        if (i == INT_RBRACKET) {
+            if (!_parsingContext.inArray()) {
+                _reportMismatchedEndMarker(i, '}');
+            }
+            _parsingContext = _parsingContext.clearAndGetParent();
+            _currToken = JsonToken.END_ARRAY;
+            return null;
+        }
+        if (i == INT_RCURLY) {
+            if (!_parsingContext.inObject()) {
+                _reportMismatchedEndMarker(i, ']');
+            }
+            _parsingContext = _parsingContext.clearAndGetParent();
+            _currToken = JsonToken.END_OBJECT;
+            return null;
         }
 
         // Nope: do we then expect a comma?
@@ -591,216 +548,22 @@ public class UTF8DataInputJsonParser
                 _reportUnexpectedChar(i, "was expecting comma to separate "+_parsingContext.typeDesc()+" entries");
             }
             i = _skipWS();
-
-            // Was that a trailing comma?
-            if (Feature.ALLOW_TRAILING_COMMA.enabledIn(_features)) {
-                if (i == INT_RBRACKET || i == INT_RCURLY) {
-                    _closeScope(i);
-                    return _currToken;
-                }
-            }
         }
-
-        /* And should we now have a name? Always true for
-         * Object contexts, since the intermediate 'expect-value'
-         * state is never retained.
-         */
         if (!_parsingContext.inObject()) {
-            return _nextTokenNotInObject(i);
+            _nextTokenNotInObject(i);
+            return null;
         }
-        // So first parse the field name itself:
-        String n = _parseName(i);
-        _parsingContext.setCurrentName(n);
+
+        final String nameStr = _parseName(i);
+        _parsingContext.setCurrentName(nameStr);
         _currToken = JsonToken.FIELD_NAME;
 
         i = _skipColon();
-
-        // Ok: we must have a value... what is it? Strings are very common, check first:
         if (i == INT_QUOTE) {
             _tokenIncomplete = true;
             _nextToken = JsonToken.VALUE_STRING;
-            return _currToken;
-        }        
-        JsonToken t;
-
-        switch (i) {
-        case '-':
-            t = _parseNegNumber();
-            break;
-
-            /* Should we have separate handling for plus? Although
-             * it is not allowed per se, it may be erroneously used,
-             * and could be indicate by a more specific error message.
-             */
-        case '0':
-        case '1':
-        case '2':
-        case '3':
-        case '4':
-        case '5':
-        case '6':
-        case '7':
-        case '8':
-        case '9':
-            t = _parsePosNumber(i);
-            break;
-        case 'f':
-            _matchToken("false", 1);
-             t = JsonToken.VALUE_FALSE;
-            break;
-        case 'n':
-            _matchToken("null", 1);
-            t = JsonToken.VALUE_NULL;
-            break;
-        case 't':
-            _matchToken("true", 1);
-            t = JsonToken.VALUE_TRUE;
-            break;
-        case '[':
-            t = JsonToken.START_ARRAY;
-            break;
-        case '{':
-            t = JsonToken.START_OBJECT;
-            break;
-
-        default:
-            t = _handleUnexpectedValue(i);
-        }
-        _nextToken = t;
-        return _currToken;
-    }
-
-    private final JsonToken _nextTokenNotInObject(int i) throws IOException
-    {
-        if (i == INT_QUOTE) {
-            _tokenIncomplete = true;
-            return (_currToken = JsonToken.VALUE_STRING);
-        }
-        switch (i) {
-        case '[':
-            _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
-            return (_currToken = JsonToken.START_ARRAY);
-        case '{':
-            _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
-            return (_currToken = JsonToken.START_OBJECT);
-        case 't':
-            _matchToken("true", 1);
-            return (_currToken = JsonToken.VALUE_TRUE);
-        case 'f':
-            _matchToken("false", 1);
-            return (_currToken = JsonToken.VALUE_FALSE);
-        case 'n':
-            _matchToken("null", 1);
-            return (_currToken = JsonToken.VALUE_NULL);
-        case '-':
-            return (_currToken = _parseNegNumber());
-            /* Should we have separate handling for plus? Although
-             * it is not allowed per se, it may be erroneously used,
-             * and could be indicated by a more specific error message.
-             */
-        case '0':
-        case '1':
-        case '2':
-        case '3':
-        case '4':
-        case '5':
-        case '6':
-        case '7':
-        case '8':
-        case '9':
-            return (_currToken = _parsePosNumber(i));
-        }
-        return (_currToken = _handleUnexpectedValue(i));
-    }
-    
-    private final JsonToken _nextAfterName()
-    {
-        _nameCopied = false; // need to invalidate if it was copied
-        JsonToken t = _nextToken;
-        _nextToken = null;
-        
-        // Also: may need to start new context?
-        if (t == JsonToken.START_ARRAY) {
-            _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
-        } else if (t == JsonToken.START_OBJECT) {
-            _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
-        }
-        return (_currToken = t);
-    }
-
-    @Override
-    public void finishToken() throws IOException {
-        if (_tokenIncomplete) {
-            _tokenIncomplete = false;
-            _finishString(); // only strings can be incomplete
-        }
-    }
-
-    /*
-    /**********************************************************
-    /* Public API, traversal, nextXxxValue/nextFieldName
-    /**********************************************************
-     */
-
-    // Can not implement without look-ahead...
-//    public boolean nextFieldName(SerializableString str) throws IOException
-
-    @Override
-    public String nextFieldName() throws IOException
-    {
-        // // // Note: this is almost a verbatim copy of nextToken()
-
-        _numTypesValid = NR_UNKNOWN;
-        if (_currToken == JsonToken.FIELD_NAME) {
-            _nextAfterName();
-            return null;
-        }
-        if (_tokenIncomplete) {
-            _skipString();
-        }
-        int i = _skipWS();
-        _binaryValue = null;
-        _tokenInputRow = _currInputRow;
-
-        if (i == INT_RBRACKET) {
-            if (!_parsingContext.inArray()) {
-                _reportMismatchedEndMarker(i, '}');
-            }
-            _parsingContext = _parsingContext.clearAndGetParent();
-            _currToken = JsonToken.END_ARRAY;
-            return null;
-        }
-        if (i == INT_RCURLY) {
-            if (!_parsingContext.inObject()) {
-                _reportMismatchedEndMarker(i, ']');
-            }
-            _parsingContext = _parsingContext.clearAndGetParent();
-            _currToken = JsonToken.END_OBJECT;
-            return null;
-        }
-
-        // Nope: do we then expect a comma?
-        if (_parsingContext.expectComma()) {
-            if (i != INT_COMMA) {
-                _reportUnexpectedChar(i, "was expecting comma to separate "+_parsingContext.typeDesc()+" entries");
-            }
-            i = _skipWS();
-        }
-        if (!_parsingContext.inObject()) {
-            _nextTokenNotInObject(i);
-            return null;
-        }
-
-        final String nameStr = _parseName(i);
-        _parsingContext.setCurrentName(nameStr);
-        _currToken = JsonToken.FIELD_NAME;
-
-        i = _skipColon();
-        if (i == INT_QUOTE) {
-            _tokenIncomplete = true;
-            _nextToken = JsonToken.VALUE_STRING;
-            return nameStr;
-        }
+            return nameStr;
+        }
         JsonToken t;
         switch (i) {
         case '-':
@@ -842,79 +605,7 @@ public class UTF8DataInputJsonParser
         }
         _nextToken = t;
         return nameStr;
-    }
-
-    @Override
-    public String nextTextValue() throws IOException
-    {
-        // two distinct cases; either got name and we know next type, or 'other'
-        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
-            _nameCopied = false;
-            JsonToken t = _nextToken;
-            _nextToken = null;
-            _currToken = t;
-            if (t == JsonToken.VALUE_STRING) {
-                if (_tokenIncomplete) {
-                    _tokenIncomplete = false;
-                    return _finishAndReturnString();
-                }
-                return _textBuffer.contentsAsString();
-            }
-            if (t == JsonToken.START_ARRAY) {
-                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
-            } else if (t == JsonToken.START_OBJECT) {
-                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
-            }
-            return null;
-        }
-        return (nextToken() == JsonToken.VALUE_STRING) ? getText() : null;
-    }
-
-    @Override
-    public int nextIntValue(int defaultValue) throws IOException
-    {
-        // two distinct cases; either got name and we know next type, or 'other'
-        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
-            _nameCopied = false;
-            JsonToken t = _nextToken;
-            _nextToken = null;
-            _currToken = t;
-            if (t == JsonToken.VALUE_NUMBER_INT) {
-                return getIntValue();
-            }
-            if (t == JsonToken.START_ARRAY) {
-                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
-            } else if (t == JsonToken.START_OBJECT) {
-                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
-            }
-            return defaultValue;
-        }
-        return (nextToken() == JsonToken.VALUE_NUMBER_INT) ? getIntValue() : defaultValue;
-    }
-
-    @Override
-    public long nextLongValue(long defaultValue) throws IOException
-    {
-        // two distinct cases; either got name and we know next type, or 'other'
-        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
-            _nameCopied = false;
-            JsonToken t = _nextToken;
-            _nextToken = null;
-            _currToken = t;
-            if (t == JsonToken.VALUE_NUMBER_INT) {
-                return getLongValue();
-            }
-            if (t == JsonToken.START_ARRAY) {
-                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
-            } else if (t == JsonToken.START_OBJECT) {
-                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
-            }
-            return defaultValue;
-        }
-        return (nextToken() == JsonToken.VALUE_NUMBER_INT) ? getLongValue() : defaultValue;
-    }
-
-    @Override
+    }@Override
     public Boolean nextBooleanValue() throws IOException
     {
         // two distinct cases; either got name and we know next type, or 'other'
@@ -945,214 +636,387 @@ public class UTF8DataInputJsonParser
             return Boolean.FALSE;
         }
         return null;
-    }
-
-    /*
-    /**********************************************************
-    /* Internal methods, number parsing
-    /**********************************************************
-     */
-
-    /**
-     * Initial parsing method for number values. It needs to be able
-     * to parse enough input to be able to determine whether the
-     * value is to be considered a simple integer value, or a more
-     * generic decimal value: latter of which needs to be expressed
-     * as a floating point number. The basic rule is that if the number
-     * has no fractional or exponential part, it is an integer; otherwise
-     * a floating point number.
-     *<p>
-     * Because much of input has to be processed in any case, no partial
-     * parsing is done: all input text will be stored for further
-     * processing. However, actual numeric value conversion will be
-     * deferred, since it is usually the most complicated and costliest
-     * part of processing.
-     */
-    protected JsonToken _parsePosNumber(int c) throws IOException
+    }// // // Let's override default impls for improved performance
+    @Override
+    public String getValueAsString() throws IOException
     {
-        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
-        int outPtr;
-
-        // One special case: if first char is 0, must not be followed by a digit.
-        // Gets bit tricky as we only want to retain 0 if it's the full value
-        if (c == INT_0) {
-            c = _handleLeadingZeroes();
-            if (c <= INT_9 && c >= INT_0) { // skip if followed by digit
-                outPtr = 0;
-            } else {
-                outBuf[0] = '0';
-                outPtr = 1;
+        if (_currToken == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                return _finishAndReturnString(); // only strings can be incomplete
             }
-        } else {
-            outBuf[0] = (char) c;
-            c = _inputData.readUnsignedByte();
-            outPtr = 1;
+            return _textBuffer.contentsAsString();
         }
-        int intLen = outPtr;
-
-        // With this, we have a nice and tight loop:
-        while (c <= INT_9 && c >= INT_0) {
-            ++intLen;
-            outBuf[outPtr++] = (char) c;
-            c = _inputData.readUnsignedByte();
+        if (_currToken == JsonToken.FIELD_NAME) {
+            return getCurrentName();
         }
-        if (c == '.' || c == 'e' || c == 'E') {
-            return _parseFloat(outBuf, outPtr, c, false, intLen);
+        return super.getValueAsString(null);
+    }@Override
+    public String getValueAsString(String defValue) throws IOException
+    {
+        if (_currToken == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                return _finishAndReturnString(); // only strings can be incomplete
+            }
+            return _textBuffer.contentsAsString();
         }
-        _textBuffer.setCurrentLength(outPtr);
-        // As per [core#105], need separating space between root values; check here
-        if (_parsingContext.inRoot()) {
-            _verifyRootSpace();
-        } else {
-            _nextByte = c;
+        if (_currToken == JsonToken.FIELD_NAME) {
+            return getCurrentName();
         }
-        // And there we have it!
-        return resetInt(false, intLen);
-    }
-    
-    protected JsonToken _parseNegNumber() throws IOException
+        return super.getValueAsString(defValue);
+    }@Override
+    public int getValueAsInt() throws IOException
     {
-        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
-        int outPtr = 0;
-
-        // Need to prepend sign?
-        outBuf[outPtr++] = '-';
-        int c = _inputData.readUnsignedByte();
-        outBuf[outPtr++] = (char) c;
-        // Note: must be followed by a digit
-        if (c <= INT_0) {
-            // One special case: if first char is 0 need to check no leading zeroes
-            if (c == INT_0) {
-                c = _handleLeadingZeroes();
-            } else {
-                return _handleInvalidNumberStart(c, true);
-            }
-        } else {
-            if (c > INT_9) {
-                return _handleInvalidNumberStart(c, true);
+        JsonToken t = _currToken;
+        if ((t == JsonToken.VALUE_NUMBER_INT) || (t == JsonToken.VALUE_NUMBER_FLOAT)) {
+            // inlined 'getIntValue()'
+            if ((_numTypesValid & NR_INT) == 0) {
+                if (_numTypesValid == NR_UNKNOWN) {
+                    return _parseIntValue();
+                }
+                if ((_numTypesValid & NR_INT) == 0) {
+                    convertNumberToInt();
+                }
             }
-            c = _inputData.readUnsignedByte();
-        }
-        // Ok: we can first just add digit we saw first:
-        int intLen = 1;
-
-        // With this, we have a nice and tight loop:
-        while (c <= INT_9 && c >= INT_0) {
-            ++intLen;
-            outBuf[outPtr++] = (char) c;
-            c = _inputData.readUnsignedByte();
+            return _numberInt;
         }
-        if (c == '.' || c == 'e' || c == 'E') {
-            return _parseFloat(outBuf, outPtr, c, true, intLen);
+        return super.getValueAsInt(0);
+    }@Override
+    public int getValueAsInt(int defValue) throws IOException
+    {
+        JsonToken t = _currToken;
+        if ((t == JsonToken.VALUE_NUMBER_INT) || (t == JsonToken.VALUE_NUMBER_FLOAT)) {
+            // inlined 'getIntValue()'
+            if ((_numTypesValid & NR_INT) == 0) {
+                if (_numTypesValid == NR_UNKNOWN) {
+                    return _parseIntValue();
+                }
+                if ((_numTypesValid & NR_INT) == 0) {
+                    convertNumberToInt();
+                }
+            }
+            return _numberInt;
         }
-        _textBuffer.setCurrentLength(outPtr);
-        // As per [core#105], need separating space between root values; check here
-        _nextByte = c;
-        if (_parsingContext.inRoot()) {
-            _verifyRootSpace();
+        return super.getValueAsInt(defValue);
+    }@Override
+    public JsonLocation getTokenLocation() {
+        return new JsonLocation(_getSourceReference(), -1L, -1L, _tokenInputRow, -1);
+    }@Override
+    public int getTextOffset() throws IOException
+    {
+        // Most have offset of 0, only some may have other values:
+        if (_currToken != null) {
+            switch (_currToken.id()) {
+            case ID_FIELD_NAME:
+                return 0;
+            case ID_STRING:
+                if (_tokenIncomplete) {
+                    _tokenIncomplete = false;
+                    _finishString(); // only strings can be incomplete
+                }
+                // fall through
+            case ID_NUMBER_INT:
+            case ID_NUMBER_FLOAT:
+                return _textBuffer.getTextOffset();
+            default:
+            }
         }
-        // And there we have it!
-        return resetInt(true, intLen);
-    }
-
-    /**
-     * Method called when we have seen one zero, and want to ensure
-     * it is not followed by another, or, if leading zeroes allowed,
-     * skipped redundant ones.
-     *
-     * @return Character immediately following zeroes
-     */
-    private final int _handleLeadingZeroes() throws IOException
+        return 0;
+    }@Override
+    public int getTextLength() throws IOException
     {
-        int ch = _inputData.readUnsignedByte();
-        // if not followed by a number (probably '.'); return zero as is, to be included
-        if (ch < INT_0 || ch > INT_9) {
-            return ch;
+        if (_currToken == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                _finishString(); // only strings can be incomplete
+            }
+            return _textBuffer.size();
         }
-        // we may want to allow leading zeroes them, after all...
-        if (!isEnabled(Feature.ALLOW_NUMERIC_LEADING_ZEROS)) {
-            reportInvalidNumber("Leading zeroes not allowed");
+        if (_currToken == JsonToken.FIELD_NAME) {
+            return _parsingContext.getCurrentName().length();
         }
-        // if so, just need to skip either all zeroes (if followed by number); or all but one (if non-number)
-        while (ch == INT_0) {
-            ch = _inputData.readUnsignedByte();
+        if (_currToken != null) { // null only before/after document
+            if (_currToken.isNumeric()) {
+                return _textBuffer.size();
+            }
+            return _currToken.asCharArray().length;
         }
-        return ch;
-    }
-
-    private final JsonToken _parseFloat(char[] outBuf, int outPtr, int c,
-            boolean negative, int integerPartLength) throws IOException
+        return 0;
+    }@Override
+    public char[] getTextCharacters() throws IOException
     {
-        int fractLen = 0;
-
-        // And then see if we get other parts
-        if (c == INT_PERIOD) { // yes, fraction
-            outBuf[outPtr++] = (char) c;
+        if (_currToken != null) { // null only before/after document
+            switch (_currToken.id()) {
 
-            fract_loop:
-            while (true) {
-                c = _inputData.readUnsignedByte();
-                if (c < INT_0 || c > INT_9) {
-                    break fract_loop;
+            case ID_FIELD_NAME:
+                if (!_nameCopied) {
+                    String name = _parsingContext.getCurrentName();
+                    int nameLen = name.length();
+                    if (_nameCopyBuffer == null) {
+                        _nameCopyBuffer = _ioContext.allocNameCopyBuffer(nameLen);
+                    } else if (_nameCopyBuffer.length < nameLen) {
+                        _nameCopyBuffer = new char[nameLen];
+                    }
+                    name.getChars(0, nameLen, _nameCopyBuffer, 0);
+                    _nameCopied = true;
                 }
-                ++fractLen;
-                if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
-                    outPtr = 0;
+                return _nameCopyBuffer;
+
+            case ID_STRING:
+                if (_tokenIncomplete) {
+                    _tokenIncomplete = false;
+                    _finishString(); // only strings can be incomplete
                 }
-                outBuf[outPtr++] = (char) c;
+                // fall through
+            case ID_NUMBER_INT:
+            case ID_NUMBER_FLOAT:
+                return _textBuffer.getTextBuffer();
+
+            default:
+                return _currToken.asCharArray();
             }
-            // must be followed by sequence of ints, one minimum
-            if (fractLen == 0) {
-                reportUnexpectedNumberChar(c, "Decimal point not followed by a digit");
+        }
+        return null;
+    }@Override
+    public String getText() throws IOException
+    {
+        if (_currToken == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                return _finishAndReturnString(); // only strings can be incomplete
             }
+            return _textBuffer.contentsAsString();
         }
-
-        int expLen = 0;
-        if (c == INT_e || c == INT_E) { // exponent?
-            if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
-                outPtr = 0;
+        return _getText2(_currToken);
+    }@Override
+    public int getText(Writer writer) throws IOException
+    {
+        JsonToken t = _currToken;
+        if (t == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                _finishString(); // only strings can be incomplete
             }
-            outBuf[outPtr++] = (char) c;
-            c = _inputData.readUnsignedByte();
-            // Sign indicator?
-            if (c == '-' || c == '+') {
-                if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
-                    outPtr = 0;
-                }
-                outBuf[outPtr++] = (char) c;
-                c = _inputData.readUnsignedByte();
+            return _textBuffer.contentsToWriter(writer);
+        }
+        if (t == JsonToken.FIELD_NAME) {
+            String n = _parsingContext.getCurrentName();
+            writer.write(n);
+            return n.length();
+        }
+        if (t != null) {
+            if (t.isNumeric()) {
+                return _textBuffer.contentsToWriter(writer);
             }
-            while (c <= INT_9 && c >= INT_0) {
-                ++expLen;
-                if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
-                    outPtr = 0;
-                }
-                outBuf[outPtr++] = (char) c;
-                c = _inputData.readUnsignedByte();
+            char[] ch = t.asCharArray();
+            writer.write(ch);
+            return ch.length;
+        }
+        return 0;
+    }@Override
+    public Object getInputSource() {
+        return _inputData;
+    }@Override
+    public JsonLocation getCurrentLocation() {
+        return new JsonLocation(_getSourceReference(), -1L, -1L, _currInputRow, -1);
+    }@Override
+    public ObjectCodec getCodec() {
+        return _objectCodec;
+    }@Override
+    public byte[] getBinaryValue(Base64Variant b64variant) throws IOException
+    {
+        if (_currToken != JsonToken.VALUE_STRING &&
+                (_currToken != JsonToken.VALUE_EMBEDDED_OBJECT || _binaryValue == null)) {
+            _reportError("Current token ("+_currToken+") not VALUE_STRING or VALUE_EMBEDDED_OBJECT, can not access as binary");
+        }
+        /* To ensure that we won't see inconsistent data, better clear up
+         * state...
+         */
+        if (_tokenIncomplete) {
+            try {
+                _binaryValue = _decodeBase64(b64variant);
+            } catch (IllegalArgumentException iae) {
+                throw _constructError("Failed to decode VALUE_STRING as base64 ("+b64variant+"): "+iae.getMessage());
             }
-            // must be followed by sequence of ints, one minimum
-            if (expLen == 0) {
-                reportUnexpectedNumberChar(c, "Exponent indicator not followed by a digit");
+            /* let's clear incomplete only now; allows for accessing other
+             * textual content in error cases
+             */
+            _tokenIncomplete = false;
+        } else { // may actually require conversion...
+            if (_binaryValue == null) {
+                @SuppressWarnings("resource")
+                ByteArrayBuilder builder = _getByteArrayBuilder();
+                _decodeBase64(getText(), builder, b64variant);
+                _binaryValue = builder.toByteArray();
             }
         }
+        return _binaryValue;
+    }@Override
+    public void finishToken() throws IOException {
+        if (_tokenIncomplete) {
+            _tokenIncomplete = false;
+            _finishString(); // only strings can be incomplete
+        }
+    }private final String findName(int q1, int lastQuadBytes) throws JsonParseException
+    {
+        q1 = pad(q1, lastQuadBytes);
+        // Usually we'll find it from the canonical symbol table already
+        String name = _symbols.findName(q1);
+        if (name != null) {
+            return name;
+        }
+        // If not, more work. We'll need add stuff to buffer
+        _quadBuffer[0] = q1;
+        return addName(_quadBuffer, 1, lastQuadBytes);
+    }private final String findName(int q1, int q2, int lastQuadBytes) throws JsonParseException
+    {
+        q2 = pad(q2, lastQuadBytes);
+        // Usually we'll find it from the canonical symbol table already
+        String name = _symbols.findName(q1, q2);
+        if (name != null) {
+            return name;
+        }
+        // If not, more work. We'll need add stuff to buffer
+        _quadBuffer[0] = q1;
+        _quadBuffer[1] = q2;
+        return addName(_quadBuffer, 2, lastQuadBytes);
+    }private final String findName(int q1, int q2, int q3, int lastQuadBytes) throws JsonParseException
+    {
+        q3 = pad(q3, lastQuadBytes);
+        String name = _symbols.findName(q1, q2, q3);
+        if (name != null) {
+            return name;
+        }
+        int[] quads = _quadBuffer;
+        quads[0] = q1;
+        quads[1] = q2;
+        quads[2] = pad(q3, lastQuadBytes);
+        return addName(quads, 3, lastQuadBytes);
+    }private final String findName(int[] quads, int qlen, int lastQuad, int lastQuadBytes) throws JsonParseException
+    {
+        if (qlen >= quads.length) {
+            _quadBuffer = quads = _growArrayBy(quads, quads.length);
+        }
+        quads[qlen++] = pad(lastQuad, lastQuadBytes);
+        String name = _symbols.findName(quads, qlen);
+        if (name == null) {
+            return addName(quads, qlen, lastQuadBytes);
+        }
+        return name;
+    } /**
+     * This is the main workhorse method used when we take a symbol
+     * table miss. It needs to demultiplex individual bytes, decode
+     * multi-byte chars (if any), and then construct Name instance
+     * and add it to the symbol table.
+     */
+    private final String addName(int[] quads, int qlen, int lastQuadBytes) throws JsonParseException
+    {
+        /* Ok: must decode UTF-8 chars. No other validation is
+         * needed, since unescaping has been done earlier as necessary
+         * (as well as error reporting for unescaped control chars)
+         */
+        // 4 bytes per quad, except last one maybe less
+        int byteLen = (qlen << 2) - 4 + lastQuadBytes;
 
-        // Ok; unless we hit end-of-input, need to push last char read back
-        // As per #105, need separating space between root values; check here
-        _nextByte = c;
-        if (_parsingContext.inRoot()) {
-            _verifyRootSpace();
+        /* And last one is not correctly aligned (leading zero bytes instead
+         * need to shift a bit, instead of trailing). Only need to shift it
+         * for UTF-8 decoding; need revert for storage (since key will not
+         * be aligned, to optimize lookup speed)
+         */
+        int lastQuad;
+
+        if (lastQuadBytes < 4) {
+            lastQuad = quads[qlen-1];
+            // 8/16/24 bit left shift
+            quads[qlen-1] = (lastQuad << ((4 - lastQuadBytes) << 3));
+        } else {
+            lastQuad = 0;
         }
-        _textBuffer.setCurrentLength(outPtr);
 
-        // And there we have it!
-        return resetFloat(negative, integerPartLength, fractLen, expLen);
-    }
+        // Need some working space, TextBuffer works well:
+        char[] cbuf = _textBuffer.emptyAndGetCurrentSegment();
+        int cix = 0;
 
-    /**
+        for (int ix = 0; ix < byteLen; ) {
+            int ch = quads[ix >> 2]; // current quad, need to shift+mask
+            int byteIx = (ix & 3);
+            ch = (ch >> ((3 - byteIx) << 3)) & 0xFF;
+            ++ix;
+
+            if (ch > 127) { // multi-byte
+                int needed;
+                if ((ch & 0xE0) == 0xC0) { // 2 bytes (0x0080 - 0x07FF)
+                    ch &= 0x1F;
+                    needed = 1;
+                } else if ((ch & 0xF0) == 0xE0) { // 3 bytes (0x0800 - 0xFFFF)
+                    ch &= 0x0F;
+                    needed = 2;
+                } else if ((ch & 0xF8) == 0xF0) { // 4 bytes; double-char with surrogates and all...
+                    ch &= 0x07;
+                    needed = 3;
+                } else { // 5- and 6-byte chars not valid xml chars
+                    _reportInvalidInitial(ch);
+                    needed = ch = 1; // never really gets this far
+                }
+                if ((ix + needed) > byteLen) {
+                    _reportInvalidEOF(" in field name", JsonToken.FIELD_NAME);
+                }
+
+                // Ok, always need at least one more:
+                int ch2 = quads[ix >> 2]; // current quad, need to shift+mask
+                byteIx = (ix & 3);
+                ch2 = (ch2 >> ((3 - byteIx) << 3));
+                ++ix;
+
+                if ((ch2 & 0xC0) != 0x080) {
+                    _reportInvalidOther(ch2);
+                }
+                ch = (ch << 6) | (ch2 & 0x3F);
+                if (needed > 1) {
+                    ch2 = quads[ix >> 2];
+                    byteIx = (ix & 3);
+                    ch2 = (ch2 >> ((3 - byteIx) << 3));
+                    ++ix;
+
+                    if ((ch2 & 0xC0) != 0x080) {
+                        _reportInvalidOther(ch2);
+                    }
+                    ch = (ch << 6) | (ch2 & 0x3F);
+                    if (needed > 2) { // 4 bytes? (need surrogates on output)
+                        ch2 = quads[ix >> 2];
+                        byteIx = (ix & 3);
+                        ch2 = (ch2 >> ((3 - byteIx) << 3));
+                        ++ix;
+                        if ((ch2 & 0xC0) != 0x080) {
+                            _reportInvalidOther(ch2 & 0xFF);
+                        }
+                        ch = (ch << 6) | (ch2 & 0x3F);
+                    }
+                }
+                if (needed > 2) { // surrogate pair? once again, let's output one here, one later on
+                    ch -= 0x10000; // to normalize it starting with 0x0
+                    if (cix >= cbuf.length) {
+                        cbuf = _textBuffer.expandCurrentSegment();
+                    }
+                    cbuf[cix++] = (char) (0xD800 + (ch >> 10));
+                    ch = 0xDC00 | (ch & 0x03FF);
+                }
+            }
+            if (cix >= cbuf.length) {
+                cbuf = _textBuffer.expandCurrentSegment();
+            }
+            cbuf[cix++] = (char) ch;
+        }
+
+        // Ok. Now we have the character array, and can construct the String
+        String baseName = new String(cbuf, 0, cix);
+        // And finally, un-align if necessary
+        if (lastQuadBytes < 4) {
+            quads[qlen-1] = lastQuad;
+        }
+        return _symbols.addName(baseName, quads, qlen);
+    } /**
      * Method called to ensure that a root-value is followed by a space token,
      * if possible.
      *<p>
@@ -1171,381 +1035,858 @@ public class UTF8DataInputJsonParser
             return;
         }
         _reportMissingRootWS(ch);
-    }
-
-    /*
-    /**********************************************************
-    /* Internal methods, secondary parsing
-    /**********************************************************
+    }private final boolean _skipYAMLComment() throws IOException
+    {
+        if (!isEnabled(Feature.ALLOW_YAML_COMMENTS)) {
+            return false;
+        }
+        _skipLine();
+        return true;
+    } /**
+     * Alternative to {@link #_skipWS} that handles possible {@link EOFException}
+     * caused by trying to read past the end of {@link InputData}.
+     *
+     * @since 2.9
      */
-    
-    protected final String _parseName(int i) throws IOException
+    private final int _skipWSOrEnd() throws IOException
     {
-        if (i != INT_QUOTE) {
-            return _handleOddName(i);
+        int i = _nextByte;
+        if (i < 0) {
+            try {
+                i = _inputData.readUnsignedByte();
+            } catch (EOFException e) {
+                return _eofAsNextChar();
+            }
+        } else {
+            _nextByte = -1;
         }
-        // If so, can also unroll loops nicely
-        /* 25-Nov-2008, tatu: This may seem weird, but here we do
-         *   NOT want to worry about UTF-8 decoding. Rather, we'll
-         *   assume that part is ok (if not it will get caught
-         *   later on), and just handle quotes and backslashes here.
-         */
-        final int[] codes = _icLatin1;
-
-        int q = _inputData.readUnsignedByte();
-
-        if (codes[q] == 0) {
-            i = _inputData.readUnsignedByte();
-            if (codes[i] == 0) {
-                q = (q << 8) | i;
-                i = _inputData.readUnsignedByte();
-                if (codes[i] == 0) {
-                    q = (q << 8) | i;
-                    i = _inputData.readUnsignedByte();
-                    if (codes[i] == 0) {
-                        q = (q << 8) | i;
-                        i = _inputData.readUnsignedByte();
-                        if (codes[i] == 0) {
-                            _quad1 = q;
-                            return _parseMediumName(i);
-                        }
-                        if (i == INT_QUOTE) { // 4 byte/char case or broken
-                            return findName(q, 4);
-                        }
-                        return parseName(q, i, 4);
-                    }
-                    if (i == INT_QUOTE) { // 3 byte/char case or broken
-                        return findName(q, 3);
-                    }
-                    return parseName(q, i, 3);
-                }                
-                if (i == INT_QUOTE) { // 2 byte/char case or broken
-                    return findName(q, 2);
+        while (true) {
+            if (i > INT_SPACE) {
+                if (i == INT_SLASH || i == INT_HASH) {
+                    return _skipWSComment(i);
+                }
+                return i;
+            } else {
+                // 06-May-2016, tatu: Could verify validity of WS, but for now why bother.
+                //   ... but line number is useful thingy
+                if (i == INT_CR || i == INT_LF) {
+                    ++_currInputRow;
                 }
-                return parseName(q, i, 2);
             }
-            if (i == INT_QUOTE) { // one byte/char case or broken
-                return findName(q, 1);
+            try {
+                i = _inputData.readUnsignedByte();
+            } catch (EOFException e) {
+                return _eofAsNextChar();
             }
-            return parseName(q, i, 1);
-        }     
-        if (q == INT_QUOTE) { // special case, ""
-            return "";
         }
-        return parseName(0, q, 0); // quoting or invalid char
-    }
-
-    private final String _parseMediumName(int q2) throws IOException
+    }private final int _skipWSComment(int i) throws IOException
     {
-        final int[] codes = _icLatin1;
-
-        // Ok, got 5 name bytes so far
-        int i = _inputData.readUnsignedByte();
-        if (codes[i] != 0) {
-            if (i == INT_QUOTE) { // 5 bytes
-                return findName(_quad1, q2, 1);
-            }
-            return parseName(_quad1, q2, i, 1); // quoting or invalid char
-        }
-        q2 = (q2 << 8) | i;
-        i = _inputData.readUnsignedByte();
-        if (codes[i] != 0) {
-            if (i == INT_QUOTE) { // 6 bytes
-                return findName(_quad1, q2, 2);
+        while (true) {
+            if (i > INT_SPACE) {
+                if (i == INT_SLASH) {
+                    _skipComment();
+                } else if (i == INT_HASH) {
+                    if (!_skipYAMLComment()) {
+                        return i;
+                    }
+                } else {
+                    return i;
+                }
+            } else {
+                // 06-May-2016, tatu: Could verify validity of WS, but for now why bother.
+                //   ... but line number is useful thingy
+                if (i == INT_CR || i == INT_LF) {
+                    ++_currInputRow;
+                }
+                /*
+                if ((i != INT_SPACE) && (i != INT_LF) && (i != INT_CR)) {
+                    _throwInvalidSpace(i);
+                }
+                */
             }
-            return parseName(_quad1, q2, i, 2);
+            i = _inputData.readUnsignedByte();
         }
-        q2 = (q2 << 8) | i;
-        i = _inputData.readUnsignedByte();
-        if (codes[i] != 0) {
-            if (i == INT_QUOTE) { // 7 bytes
-                return findName(_quad1, q2, 3);
-            }
-            return parseName(_quad1, q2, i, 3);
+    }private final int _skipWS() throws IOException
+    {
+        int i = _nextByte;
+        if (i < 0) {
+            i = _inputData.readUnsignedByte();
+        } else {
+            _nextByte = -1;
         }
-        q2 = (q2 << 8) | i;
-        i = _inputData.readUnsignedByte();
-        if (codes[i] != 0) {
-            if (i == INT_QUOTE) { // 8 bytes
-                return findName(_quad1, q2, 4);
+        while (true) {
+            if (i > INT_SPACE) {
+                if (i == INT_SLASH || i == INT_HASH) {
+                    return _skipWSComment(i);
+                }
+                return i;
+            } else {
+                // 06-May-2016, tatu: Could verify validity of WS, but for now why bother.
+                //   ... but line number is useful thingy
+                if (i == INT_CR || i == INT_LF) {
+                    ++_currInputRow;
+                }
             }
-            return parseName(_quad1, q2, i, 4);
+            i = _inputData.readUnsignedByte();
         }
-        return _parseMediumName2(i, q2);
-    }
-
-    private final String _parseMediumName2(int q3, final int q2) throws IOException
+    }private final void _skipUtf8_4() throws IOException
     {
-        final int[] codes = _icLatin1;
-
-        // Got 9 name bytes so far
-        int i = _inputData.readUnsignedByte();
-        if (codes[i] != 0) {
-            if (i == INT_QUOTE) { // 9 bytes
-                return findName(_quad1, q2, q3, 1);
-            }
-            return parseName(_quad1, q2, q3, i, 1);
+        int d = _inputData.readUnsignedByte();
+        if ((d & 0xC0) != 0x080) {
+            _reportInvalidOther(d & 0xFF);
         }
-        q3 = (q3 << 8) | i;
-        i = _inputData.readUnsignedByte();
-        if (codes[i] != 0) {
-            if (i == INT_QUOTE) { // 10 bytes
-                return findName(_quad1, q2, q3, 2);
-            }
-            return parseName(_quad1, q2, q3, i, 2);
+        d = _inputData.readUnsignedByte();
+        if ((d & 0xC0) != 0x080) {
+            _reportInvalidOther(d & 0xFF);
         }
-        q3 = (q3 << 8) | i;
-        i = _inputData.readUnsignedByte();
-        if (codes[i] != 0) {
-            if (i == INT_QUOTE) { // 11 bytes
-                return findName(_quad1, q2, q3, 3);
-            }
-            return parseName(_quad1, q2, q3, i, 3);
+        d = _inputData.readUnsignedByte();
+        if ((d & 0xC0) != 0x080) {
+            _reportInvalidOther(d & 0xFF);
         }
-        q3 = (q3 << 8) | i;
-        i = _inputData.readUnsignedByte();
-        if (codes[i] != 0) {
-            if (i == INT_QUOTE) { // 12 bytes
-                return findName(_quad1, q2, q3, 4);
-            }
-            return parseName(_quad1, q2, q3, i, 4);
+    }/* Alas, can't heavily optimize skipping, since we still have to
+     * do validity checks...
+     */
+    private final void _skipUtf8_3() throws IOException
+    {
+        //c &= 0x0F;
+        int c = _inputData.readUnsignedByte();
+        if ((c & 0xC0) != 0x080) {
+            _reportInvalidOther(c & 0xFF);
         }
-        return _parseLongName(i, q2, q3);
-    }
-    
-    private final String _parseLongName(int q, final int q2, int q3) throws IOException
+        c = _inputData.readUnsignedByte();
+        if ((c & 0xC0) != 0x080) {
+            _reportInvalidOther(c & 0xFF);
+        }
+    }private final void _skipUtf8_2() throws IOException
     {
-        _quadBuffer[0] = _quad1;
-        _quadBuffer[1] = q2;
-        _quadBuffer[2] = q3;
+        int c = _inputData.readUnsignedByte();
+        if ((c & 0xC0) != 0x080) {
+            _reportInvalidOther(c & 0xFF);
+        }
+    } /**
+     * Method called to skim through rest of unparsed String value,
+     * if it is not needed. This can be done bit faster if contents
+     * need not be stored for future access.
+     */
+    protected void _skipString() throws IOException
+    {
+        _tokenIncomplete = false;
 
-        // As explained above, will ignore UTF-8 encoding at this point
-        final int[] codes = _icLatin1;
-        int qlen = 3;
+        // Need to be fully UTF-8 aware here:
+        final int[] codes = _icUTF8;
 
+        main_loop:
         while (true) {
-            int i = _inputData.readUnsignedByte();
-            if (codes[i] != 0) {
-                if (i == INT_QUOTE) {
-                    return findName(_quadBuffer, qlen, q, 1);
-                }
-                return parseEscapedName(_quadBuffer, qlen, q, i, 1);
-            }
+            int c;
 
-            q = (q << 8) | i;
-            i = _inputData.readUnsignedByte();
-            if (codes[i] != 0) {
-                if (i == INT_QUOTE) {
-                    return findName(_quadBuffer, qlen, q, 2);
+            ascii_loop:
+            while (true) {
+                c = _inputData.readUnsignedByte();
+                if (codes[c] != 0) {
+                    break ascii_loop;
                 }
-                return parseEscapedName(_quadBuffer, qlen, q, i, 2);
             }
-
-            q = (q << 8) | i;
-            i = _inputData.readUnsignedByte();
-            if (codes[i] != 0) {
-                if (i == INT_QUOTE) {
-                    return findName(_quadBuffer, qlen, q, 3);
-                }
-                return parseEscapedName(_quadBuffer, qlen, q, i, 3);
+            // Ok: end marker, escape or multi-byte?
+            if (c == INT_QUOTE) {
+                break main_loop;
             }
 
-            q = (q << 8) | i;
-            i = _inputData.readUnsignedByte();
-            if (codes[i] != 0) {
-                if (i == INT_QUOTE) {
-                    return findName(_quadBuffer, qlen, q, 4);
+            switch (codes[c]) {
+            case 1: // backslash
+                _decodeEscaped();
+                break;
+            case 2: // 2-byte UTF
+                _skipUtf8_2();
+                break;
+            case 3: // 3-byte UTF
+                _skipUtf8_3();
+                break;
+            case 4: // 4-byte UTF
+                _skipUtf8_4();
+                break;
+            default:
+                if (c < INT_SPACE) {
+                    _throwUnquotedSpace(c, "string value");
+                } else {
+                    // Is this good enough error message?
+                    _reportInvalidChar(c);
                 }
-                return parseEscapedName(_quadBuffer, qlen, q, i, 4);
             }
-
-            // Nope, no end in sight. Need to grow quad array etc
-            if (qlen >= _quadBuffer.length) {
-                _quadBuffer = _growArrayBy(_quadBuffer, qlen);
-            }
-            _quadBuffer[qlen++] = q;
-            q = i;
         }
-    }
-
-    private final String parseName(int q1, int ch, int lastQuadBytes) throws IOException {
-        return parseEscapedName(_quadBuffer, 0, q1, ch, lastQuadBytes);
-    }
-
-    private final String parseName(int q1, int q2, int ch, int lastQuadBytes) throws IOException {
-        _quadBuffer[0] = q1;
-        return parseEscapedName(_quadBuffer, 1, q2, ch, lastQuadBytes);
-    }
-
-    private final String parseName(int q1, int q2, int q3, int ch, int lastQuadBytes) throws IOException {
-        _quadBuffer[0] = q1;
-        _quadBuffer[1] = q2;
-        return parseEscapedName(_quadBuffer, 2, q3, ch, lastQuadBytes);
-    }
-    
-    /**
-     * Slower parsing method which is generally branched to when
-     * an escape sequence is detected (or alternatively for long
-     * names, one crossing input buffer boundary).
-     * Needs to be able to handle more exceptional cases, gets slower,
-     * and hance is offlined to a separate method.
+    } /**
+     * Method for skipping contents of an input line; usually for CPP
+     * and YAML style comments.
      */
-    protected final String parseEscapedName(int[] quads, int qlen, int currQuad, int ch,
-            int currQuadBytes) throws IOException
+    private final void _skipLine() throws IOException
     {
-        /* 25-Nov-2008, tatu: This may seem weird, but here we do not want to worry about
-         *   UTF-8 decoding yet. Rather, we'll assume that part is ok (if not it will get
-         *   caught later on), and just handle quotes and backslashes here.
-         */
-        final int[] codes = _icLatin1;
-
+        // Ok: need to find EOF or linefeed
+        final int[] codes = CharTypes.getInputCodeComment();
         while (true) {
-            if (codes[ch] != 0) {
-                if (ch == INT_QUOTE) { // we are done
+            int i = _inputData.readUnsignedByte();
+            int code = codes[i];
+            if (code != 0) {
+                switch (code) {
+                case INT_LF:
+                case INT_CR:
+                    ++_currInputRow;
+                    return;
+                case '*': // nop for these comments
+                    break;
+                case 2: // 2-byte UTF
+                    _skipUtf8_2();
+                    break;
+                case 3: // 3-byte UTF
+                    _skipUtf8_3();
                     break;
+                case 4: // 4-byte UTF
+                    _skipUtf8_4();
+                    break;
+                default: // e.g. -1
+                    if (code < 0) {
+                        // Is this good enough error message?
+                        _reportInvalidChar(i);
+                    }
                 }
-                // Unquoted white space?
-                if (ch != INT_BACKSLASH) {
-                    // As per [JACKSON-208], call can now return:
-                    _throwUnquotedSpace(ch, "name");
-                } else {
-                    // Nope, escape sequence
-                    ch = _decodeEscaped();
+            }
+        }
+    }private final void _skipComment() throws IOException
+    {
+        if (!isEnabled(Feature.ALLOW_COMMENTS)) {
+            _reportUnexpectedChar('/', "maybe a (non-standard) comment? (not recognized as one since Feature 'ALLOW_COMMENTS' not enabled for parser)");
+        }
+        int c = _inputData.readUnsignedByte();
+        if (c == '/') {
+            _skipLine();
+        } else if (c == '*') {
+            _skipCComment();
+        } else {
+            _reportUnexpectedChar(c, "was expecting either '*' or '/' for a comment");
+        }
+    }private final int _skipColon2(int i, boolean gotColon) throws IOException
+    {
+        for (;; i = _inputData.readUnsignedByte()) {
+            if (i > INT_SPACE) {
+                if (i == INT_SLASH) {
+                    _skipComment();
+                    continue;
                 }
-                /* Oh crap. May need to UTF-8 (re-)encode it, if it's
-                 * beyond 7-bit ascii. Gets pretty messy.
-                 * If this happens often, may want to use different name
-                 * canonicalization to avoid these hits.
-                 */
-                if (ch > 127) {
-                    // Ok, we'll need room for first byte right away
-                    if (currQuadBytes >= 4) {
-                        if (qlen >= quads.length) {
-                            _quadBuffer = quads = _growArrayBy(quads, quads.length);
-                        }
-                        quads[qlen++] = currQuad;
-                        currQuad = 0;
-                        currQuadBytes = 0;
-                    }
-                    if (ch < 0x800) { // 2-byte
-                        currQuad = (currQuad << 8) | (0xc0 | (ch >> 6));
-                        ++currQuadBytes;
-                        // Second byte gets output below:
-                    } else { // 3 bytes; no need to worry about surrogates here
-                        currQuad = (currQuad << 8) | (0xe0 | (ch >> 12));
-                        ++currQuadBytes;
-                        // need room for middle byte?
-                        if (currQuadBytes >= 4) {
-                            if (qlen >= quads.length) {
-                                _quadBuffer = quads = _growArrayBy(quads, quads.length);
-                            }
-                            quads[qlen++] = currQuad;
-                            currQuad = 0;
-                            currQuadBytes = 0;
-                        }
-                        currQuad = (currQuad << 8) | (0x80 | ((ch >> 6) & 0x3f));
-                        ++currQuadBytes;
+                if (i == INT_HASH) {
+                    if (_skipYAMLComment()) {
+                        continue;
                     }
-                    // And same last byte in both cases, gets output below:
-                    ch = 0x80 | (ch & 0x3f);
                 }
-            }
-            // Ok, we have one more byte to add at any rate:
-            if (currQuadBytes < 4) {
-                ++currQuadBytes;
-                currQuad = (currQuad << 8) | ch;
+                if (gotColon) {
+                    return i;
+                }
+                if (i != INT_COLON) {
+                    _reportUnexpectedChar(i, "was expecting a colon to separate field name and value");
+                }
+                gotColon = true;
             } else {
-                if (qlen >= quads.length) {
-                    _quadBuffer = quads = _growArrayBy(quads, quads.length);
+                // 06-May-2016, tatu: Could verify validity of WS, but for now why bother.
+                //   ... but line number is useful thingy
+                if (i == INT_CR || i == INT_LF) {
+                    ++_currInputRow;
                 }
-                quads[qlen++] = currQuad;
-                currQuad = ch;
-                currQuadBytes = 1;
-            }
-            ch = _inputData.readUnsignedByte();
-        }
-
-        if (currQuadBytes > 0) {
-            if (qlen >= quads.length) {
-                _quadBuffer = quads = _growArrayBy(quads, quads.length);
             }
-            quads[qlen++] = pad(currQuad, currQuadBytes);
-        }
-        String name = _symbols.findName(quads, qlen);
-        if (name == null) {
-            name = addName(quads, qlen, currQuadBytes);
         }
-        return name;
-    }
-
-    /**
-     * Method called when we see non-white space character other
-     * than double quote, when expecting a field name.
-     * In standard mode will just throw an exception; but
-     * in non-standard modes may be able to parse name.
-     */
-    protected String _handleOddName(int ch) throws IOException
+    }private final int _skipColon() throws IOException
     {
-        if (ch == '\'' && isEnabled(Feature.ALLOW_SINGLE_QUOTES)) {
-            return _parseAposName();
-        }
-        if (!isEnabled(Feature.ALLOW_UNQUOTED_FIELD_NAMES)) {
-            char c = (char) _decodeCharForError(ch);
-            _reportUnexpectedChar(c, "was expecting double-quote to start field name");
-        }
-        /* Also: note that although we use a different table here,
-         * it does NOT handle UTF-8 decoding. It'll just pass those
-         * high-bit codes as acceptable for later decoding.
-         */
-        final int[] codes = CharTypes.getInputCodeUtf8JsNames();
-        // Also: must start with a valid character...
-        if (codes[ch] != 0) {
-            _reportUnexpectedChar(ch, "was expecting either valid name character (for unquoted name) or double-quote (for quoted) to start field name");
+        int i = _nextByte;
+        if (i < 0) {
+            i = _inputData.readUnsignedByte();
+        } else {
+            _nextByte = -1;
         }
-
-        /* Ok, now; instead of ultra-optimizing parsing here (as with
-         * regular JSON names), let's just use the generic "slow"
-         * variant. Can measure its impact later on if need be
-         */
-        int[] quads = _quadBuffer;
-        int qlen = 0;
-        int currQuad = 0;
-        int currQuadBytes = 0;
-
-        while (true) {
-            // Ok, we have one more byte to add at any rate:
-            if (currQuadBytes < 4) {
-                ++currQuadBytes;
-                currQuad = (currQuad << 8) | ch;
-            } else {
-                if (qlen >= quads.length) {
-                    _quadBuffer = quads = _growArrayBy(quads, quads.length);
+        // Fast path: colon with optional single-space/tab before and/or after:
+        if (i == INT_COLON) { // common case, no leading space
+            i = _inputData.readUnsignedByte();
+            if (i > INT_SPACE) { // nor trailing
+                if (i == INT_SLASH || i == INT_HASH) {
+                    return _skipColon2(i, true);
                 }
-                quads[qlen++] = currQuad;
-                currQuad = ch;
-                currQuadBytes = 1;
+                return i;
             }
-            ch = _inputData.readUnsignedByte();
-            if (codes[ch] != 0) {
-                break;
+            if (i == INT_SPACE || i == INT_TAB) {
+                i = _inputData.readUnsignedByte();
+                if (i > INT_SPACE) {
+                    if (i == INT_SLASH || i == INT_HASH) {
+                        return _skipColon2(i, true);
+                    }
+                    return i;
+                }
             }
+            return _skipColon2(i, true); // true -> skipped colon
         }
-        // Note: we must "push back" character read here for future consumption
-        _nextByte = ch;
-        if (currQuadBytes > 0) {
-            if (qlen >= quads.length) {
-                _quadBuffer = quads = _growArrayBy(quads, quads.length);
+        if (i == INT_SPACE || i == INT_TAB) {
+            i = _inputData.readUnsignedByte();
+        }
+        if (i == INT_COLON) {
+            i = _inputData.readUnsignedByte();
+            if (i > INT_SPACE) {
+                if (i == INT_SLASH || i == INT_HASH) {
+                    return _skipColon2(i, true);
+                }
+                return i;
             }
-            quads[qlen++] = currQuad;
+            if (i == INT_SPACE || i == INT_TAB) {
+                i = _inputData.readUnsignedByte();
+                if (i > INT_SPACE) {
+                    if (i == INT_SLASH || i == INT_HASH) {
+                        return _skipColon2(i, true);
+                    }
+                    return i;
+                }
+            }
+            return _skipColon2(i, true);
         }
-        String name = _symbols.findName(quads, qlen);
-        if (name == null) {
-            name = addName(quads, qlen, currQuadBytes);
+        return _skipColon2(i, false);
+    }private final void _skipCComment() throws IOException
+    {
+        // Need to be UTF-8 aware here to decode content (for skipping)
+        final int[] codes = CharTypes.getInputCodeComment();
+        int i = _inputData.readUnsignedByte();
+
+        // Ok: need the matching '*/'
+        main_loop:
+        while (true) {
+            int code = codes[i];
+            if (code != 0) {
+                switch (code) {
+                case '*':
+                    i = _inputData.readUnsignedByte();
+                    if (i == INT_SLASH) {
+                        return;
+                    }
+                    continue main_loop;
+                case INT_LF:
+                case INT_CR:
+                    ++_currInputRow;
+                    break;
+                case 2: // 2-byte UTF
+                    _skipUtf8_2();
+                    break;
+                case 3: // 3-byte UTF
+                    _skipUtf8_3();
+                    break;
+                case 4: // 4-byte UTF
+                    _skipUtf8_4();
+                    break;
+                default: // e.g. -1
+                    // Is this good enough error message?
+                    _reportInvalidChar(i);
+                }
+            }
+            i = _inputData.readUnsignedByte();
+        }
+    }protected void _reportInvalidToken(int ch, String matchedPart) throws IOException
+     {
+         _reportInvalidToken(ch, matchedPart, "'null', 'true', 'false' or NaN");
+     }protected void _reportInvalidToken(int ch, String matchedPart, String msg)
+        throws IOException
+     {
+         StringBuilder sb = new StringBuilder(matchedPart);
+
+         /* Let's just try to find what appears to be the token, using
+          * regular Java identifier character rules. It's just a heuristic,
+          * nothing fancy here (nor fast).
+          */
+         while (true) {
+             char c = (char) _decodeCharForError(ch);
+             if (!Character.isJavaIdentifierPart(c)) {
+                 break;
+             }
+             sb.append(c);
+             ch = _inputData.readUnsignedByte();
+         }
+         _reportError("Unrecognized token '"+sb.toString()+"': was expecting "+msg);
+     }private void _reportInvalidOther(int mask)
+        throws JsonParseException
+    {
+        _reportError("Invalid UTF-8 middle byte 0x"+Integer.toHexString(mask));
+    }protected void _reportInvalidInitial(int mask)
+        throws JsonParseException
+    {
+        _reportError("Invalid UTF-8 start byte 0x"+Integer.toHexString(mask));
+    }protected void _reportInvalidChar(int c)
+        throws JsonParseException
+    {
+        // Either invalid WS or illegal UTF-8 start char
+        if (c < INT_SPACE) {
+            _throwInvalidSpace(c);
+        }
+        _reportInvalidInitial(c);
+    } /**
+     * Method called to release internal buffers owned by the base
+     * reader. This may be called along with {@link #_closeInput} (for
+     * example, when explicitly closing this reader instance), or
+     * separately (if need be).
+     */
+    @Override
+    protected void _releaseBuffers() throws IOException
+    {
+        super._releaseBuffers();
+        // Merge found symbols, if any:
+        _symbols.release();
+    }protected int _readBinary(Base64Variant b64variant, OutputStream out,
+                              byte[] buffer) throws IOException
+    {
+        int outputPtr = 0;
+        final int outputEnd = buffer.length - 3;
+        int outputCount = 0;
+
+        while (true) {
+            // first, we'll skip preceding white space, if any
+            int ch;
+            do {
+                ch = _inputData.readUnsignedByte();
+            } while (ch <= INT_SPACE);
+            int bits = b64variant.decodeBase64Char(ch);
+            if (bits < 0) { // reached the end, fair and square?
+                if (ch == INT_QUOTE) {
+                    break;
+                }
+                bits = _decodeBase64Escape(b64variant, ch, 0);
+                if (bits < 0) { // white space to skip
+                    continue;
+                }
+            }
+
+            // enough room? If not, flush
+            if (outputPtr > outputEnd) {
+                outputCount += outputPtr;
+                out.write(buffer, 0, outputPtr);
+                outputPtr = 0;
+            }
+
+            int decodedData = bits;
+
+            // then second base64 char; can't get padding yet, nor ws
+            ch = _inputData.readUnsignedByte();
+            bits = b64variant.decodeBase64Char(ch);
+            if (bits < 0) {
+                bits = _decodeBase64Escape(b64variant, ch, 1);
+            }
+            decodedData = (decodedData << 6) | bits;
+
+            // third base64 char; can be padding, but not ws
+            ch = _inputData.readUnsignedByte();
+            bits = b64variant.decodeBase64Char(ch);
+
+            // First branch: can get padding (-> 1 byte)
+            if (bits < 0) {
+                if (bits != Base64Variant.BASE64_VALUE_PADDING) {
+                    // could also just be 'missing'  padding
+                    if (ch == '"' && !b64variant.usesPadding()) {
+                        decodedData >>= 4;
+                        buffer[outputPtr++] = (byte) decodedData;
+                        break;
+                    }
+                    bits = _decodeBase64Escape(b64variant, ch, 2);
+                }
+                if (bits == Base64Variant.BASE64_VALUE_PADDING) {
+                    // Ok, must get padding
+                    ch = _inputData.readUnsignedByte();
+                    if (!b64variant.usesPaddingChar(ch)) {
+                        throw reportInvalidBase64Char(b64variant, ch, 3, "expected padding character '"+b64variant.getPaddingChar()+"'");
+                    }
+                    // Got 12 bits, only need 8, need to shift
+                    decodedData >>= 4;
+                    buffer[outputPtr++] = (byte) decodedData;
+                    continue;
+                }
+            }
+            // Nope, 2 or 3 bytes
+            decodedData = (decodedData << 6) | bits;
+            // fourth and last base64 char; can be padding, but not ws
+            ch = _inputData.readUnsignedByte();
+            bits = b64variant.decodeBase64Char(ch);
+            if (bits < 0) {
+                if (bits != Base64Variant.BASE64_VALUE_PADDING) {
+                    // could also just be 'missing'  padding
+                    if (ch == '"' && !b64variant.usesPadding()) {
+                        decodedData >>= 2;
+                        buffer[outputPtr++] = (byte) (decodedData >> 8);
+                        buffer[outputPtr++] = (byte) decodedData;
+                        break;
+                    }
+                    bits = _decodeBase64Escape(b64variant, ch, 3);
+                }
+                if (bits == Base64Variant.BASE64_VALUE_PADDING) {
+                    /* With padding we only get 2 bytes; but we have
+                     * to shift it a bit so it is identical to triplet
+                     * case with partial output.
+                     * 3 chars gives 3x6 == 18 bits, of which 2 are
+                     * dummies, need to discard:
+                     */
+                    decodedData >>= 2;
+                    buffer[outputPtr++] = (byte) (decodedData >> 8);
+                    buffer[outputPtr++] = (byte) decodedData;
+                    continue;
+                }
+            }
+            // otherwise, our triplet is now complete
+            decodedData = (decodedData << 6) | bits;
+            buffer[outputPtr++] = (byte) (decodedData >> 16);
+            buffer[outputPtr++] = (byte) (decodedData >> 8);
+            buffer[outputPtr++] = (byte) decodedData;
+        }
+        _tokenIncomplete = false;
+        if (outputPtr > 0) {
+            outputCount += outputPtr;
+            out.write(buffer, 0, outputPtr);
+        }
+        return outputCount;
+    } /**
+     * Initial parsing method for number values. It needs to be able
+     * to parse enough input to be able to determine whether the
+     * value is to be considered a simple integer value, or a more
+     * generic decimal value: latter of which needs to be expressed
+     * as a floating point number. The basic rule is that if the number
+     * has no fractional or exponential part, it is an integer; otherwise
+     * a floating point number.
+     *<p>
+     * Because much of input has to be processed in any case, no partial
+     * parsing is done: all input text will be stored for further
+     * processing. However, actual numeric value conversion will be
+     * deferred, since it is usually the most complicated and costliest
+     * part of processing.
+     */
+    protected JsonToken _parsePosNumber(int c) throws IOException
+    {
+        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
+        int outPtr;
+
+        // One special case: if first char is 0, must not be followed by a digit.
+        // Gets bit tricky as we only want to retain 0 if it's the full value
+        if (c == INT_0) {
+            c = _handleLeadingZeroes();
+            if (c <= INT_9 && c >= INT_0) { // skip if followed by digit
+                outPtr = 0;
+            } else {
+                outBuf[0] = '0';
+                outPtr = 1;
+            }
+        } else {
+            outBuf[0] = (char) c;
+            c = _inputData.readUnsignedByte();
+            outPtr = 1;
+        }
+        int intLen = outPtr;
+
+        // With this, we have a nice and tight loop:
+        while (c <= INT_9 && c >= INT_0) {
+            ++intLen;
+            outBuf[outPtr++] = (char) c;
+            c = _inputData.readUnsignedByte();
+        }
+        if (c == '.' || c == 'e' || c == 'E') {
+            return _parseFloat(outBuf, outPtr, c, false, intLen);
+        }
+        _textBuffer.setCurrentLength(outPtr);
+        // As per [core#105], need separating space between root values; check here
+        if (_parsingContext.inRoot()) {
+            _verifyRootSpace();
+        } else {
+            _nextByte = c;
+        }
+        // And there we have it!
+        return resetInt(false, intLen);
+    }protected JsonToken _parseNegNumber() throws IOException
+    {
+        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
+        int outPtr = 0;
+
+        // Need to prepend sign?
+        outBuf[outPtr++] = '-';
+        int c = _inputData.readUnsignedByte();
+        outBuf[outPtr++] = (char) c;
+        // Note: must be followed by a digit
+        if (c <= INT_0) {
+            // One special case: if first char is 0 need to check no leading zeroes
+            if (c == INT_0) {
+                c = _handleLeadingZeroes();
+            } else {
+                return _handleInvalidNumberStart(c, true);
+            }
+        } else {
+            if (c > INT_9) {
+                return _handleInvalidNumberStart(c, true);
+            }
+            c = _inputData.readUnsignedByte();
+        }
+        // Ok: we can first just add digit we saw first:
+        int intLen = 1;
+
+        // With this, we have a nice and tight loop:
+        while (c <= INT_9 && c >= INT_0) {
+            ++intLen;
+            outBuf[outPtr++] = (char) c;
+            c = _inputData.readUnsignedByte();
+        }
+        if (c == '.' || c == 'e' || c == 'E') {
+            return _parseFloat(outBuf, outPtr, c, true, intLen);
+        }
+        _textBuffer.setCurrentLength(outPtr);
+        // As per [core#105], need separating space between root values; check here
+        _nextByte = c;
+        if (_parsingContext.inRoot()) {
+            _verifyRootSpace();
+        }
+        // And there we have it!
+        return resetInt(true, intLen);
+    }protected final String _parseName(int i) throws IOException
+    {
+        if (i != INT_QUOTE) {
+            return _handleOddName(i);
+        }
+        // If so, can also unroll loops nicely
+        /* 25-Nov-2008, tatu: This may seem weird, but here we do
+         *   NOT want to worry about UTF-8 decoding. Rather, we'll
+         *   assume that part is ok (if not it will get caught
+         *   later on), and just handle quotes and backslashes here.
+         */
+        final int[] codes = _icLatin1;
+
+        int q = _inputData.readUnsignedByte();
+
+        if (codes[q] == 0) {
+            i = _inputData.readUnsignedByte();
+            if (codes[i] == 0) {
+                q = (q << 8) | i;
+                i = _inputData.readUnsignedByte();
+                if (codes[i] == 0) {
+                    q = (q << 8) | i;
+                    i = _inputData.readUnsignedByte();
+                    if (codes[i] == 0) {
+                        q = (q << 8) | i;
+                        i = _inputData.readUnsignedByte();
+                        if (codes[i] == 0) {
+                            _quad1 = q;
+                            return _parseMediumName(i);
+                        }
+                        if (i == INT_QUOTE) { // 4 byte/char case or broken
+                            return findName(q, 4);
+                        }
+                        return parseName(q, i, 4);
+                    }
+                    if (i == INT_QUOTE) { // 3 byte/char case or broken
+                        return findName(q, 3);
+                    }
+                    return parseName(q, i, 3);
+                }
+                if (i == INT_QUOTE) { // 2 byte/char case or broken
+                    return findName(q, 2);
+                }
+                return parseName(q, i, 2);
+            }
+            if (i == INT_QUOTE) { // one byte/char case or broken
+                return findName(q, 1);
+            }
+            return parseName(q, i, 1);
+        }
+        if (q == INT_QUOTE) { // special case, ""
+            return "";
+        }
+        return parseName(0, q, 0); // quoting or invalid char
+    }private final String _parseMediumName2(int q3, final int q2) throws IOException
+    {
+        final int[] codes = _icLatin1;
+
+        // Got 9 name bytes so far
+        int i = _inputData.readUnsignedByte();
+        if (codes[i] != 0) {
+            if (i == INT_QUOTE) { // 9 bytes
+                return findName(_quad1, q2, q3, 1);
+            }
+            return parseName(_quad1, q2, q3, i, 1);
+        }
+        q3 = (q3 << 8) | i;
+        i = _inputData.readUnsignedByte();
+        if (codes[i] != 0) {
+            if (i == INT_QUOTE) { // 10 bytes
+                return findName(_quad1, q2, q3, 2);
+            }
+            return parseName(_quad1, q2, q3, i, 2);
+        }
+        q3 = (q3 << 8) | i;
+        i = _inputData.readUnsignedByte();
+        if (codes[i] != 0) {
+            if (i == INT_QUOTE) { // 11 bytes
+                return findName(_quad1, q2, q3, 3);
+            }
+            return parseName(_quad1, q2, q3, i, 3);
+        }
+        q3 = (q3 << 8) | i;
+        i = _inputData.readUnsignedByte();
+        if (codes[i] != 0) {
+            if (i == INT_QUOTE) { // 12 bytes
+                return findName(_quad1, q2, q3, 4);
+            }
+            return parseName(_quad1, q2, q3, i, 4);
+        }
+        return _parseLongName(i, q2, q3);
+    }private final String _parseMediumName(int q2) throws IOException
+    {
+        final int[] codes = _icLatin1;
+
+        // Ok, got 5 name bytes so far
+        int i = _inputData.readUnsignedByte();
+        if (codes[i] != 0) {
+            if (i == INT_QUOTE) { // 5 bytes
+                return findName(_quad1, q2, 1);
+            }
+            return parseName(_quad1, q2, i, 1); // quoting or invalid char
+        }
+        q2 = (q2 << 8) | i;
+        i = _inputData.readUnsignedByte();
+        if (codes[i] != 0) {
+            if (i == INT_QUOTE) { // 6 bytes
+                return findName(_quad1, q2, 2);
+            }
+            return parseName(_quad1, q2, i, 2);
+        }
+        q2 = (q2 << 8) | i;
+        i = _inputData.readUnsignedByte();
+        if (codes[i] != 0) {
+            if (i == INT_QUOTE) { // 7 bytes
+                return findName(_quad1, q2, 3);
+            }
+            return parseName(_quad1, q2, i, 3);
+        }
+        q2 = (q2 << 8) | i;
+        i = _inputData.readUnsignedByte();
+        if (codes[i] != 0) {
+            if (i == INT_QUOTE) { // 8 bytes
+                return findName(_quad1, q2, 4);
+            }
+            return parseName(_quad1, q2, i, 4);
+        }
+        return _parseMediumName2(i, q2);
+    }private final String _parseLongName(int q, final int q2, int q3) throws IOException
+    {
+        _quadBuffer[0] = _quad1;
+        _quadBuffer[1] = q2;
+        _quadBuffer[2] = q3;
+
+        // As explained above, will ignore UTF-8 encoding at this point
+        final int[] codes = _icLatin1;
+        int qlen = 3;
+
+        while (true) {
+            int i = _inputData.readUnsignedByte();
+            if (codes[i] != 0) {
+                if (i == INT_QUOTE) {
+                    return findName(_quadBuffer, qlen, q, 1);
+                }
+                return parseEscapedName(_quadBuffer, qlen, q, i, 1);
+            }
+
+            q = (q << 8) | i;
+            i = _inputData.readUnsignedByte();
+            if (codes[i] != 0) {
+                if (i == INT_QUOTE) {
+                    return findName(_quadBuffer, qlen, q, 2);
+                }
+                return parseEscapedName(_quadBuffer, qlen, q, i, 2);
+            }
+
+            q = (q << 8) | i;
+            i = _inputData.readUnsignedByte();
+            if (codes[i] != 0) {
+                if (i == INT_QUOTE) {
+                    return findName(_quadBuffer, qlen, q, 3);
+                }
+                return parseEscapedName(_quadBuffer, qlen, q, i, 3);
+            }
+
+            q = (q << 8) | i;
+            i = _inputData.readUnsignedByte();
+            if (codes[i] != 0) {
+                if (i == INT_QUOTE) {
+                    return findName(_quadBuffer, qlen, q, 4);
+                }
+                return parseEscapedName(_quadBuffer, qlen, q, i, 4);
+            }
+
+            // Nope, no end in sight. Need to grow quad array etc
+            if (qlen >= _quadBuffer.length) {
+                _quadBuffer = _growArrayBy(_quadBuffer, qlen);
+            }
+            _quadBuffer[qlen++] = q;
+            q = i;
+        }
+    }private final JsonToken _parseFloat(char[] outBuf, int outPtr, int c,
+            boolean negative, int integerPartLength) throws IOException
+    {
+        int fractLen = 0;
+
+        // And then see if we get other parts
+        if (c == INT_PERIOD) { // yes, fraction
+            outBuf[outPtr++] = (char) c;
+
+            fract_loop:
+            while (true) {
+                c = _inputData.readUnsignedByte();
+                if (c < INT_0 || c > INT_9) {
+                    break fract_loop;
+                }
+                ++fractLen;
+                if (outPtr >= outBuf.length) {
+                    outBuf = _textBuffer.finishCurrentSegment();
+                    outPtr = 0;
+                }
+                outBuf[outPtr++] = (char) c;
+            }
+            // must be followed by sequence of ints, one minimum
+            if (fractLen == 0) {
+                reportUnexpectedNumberChar(c, "Decimal point not followed by a digit");
+            }
+        }
+
+        int expLen = 0;
+        if (c == INT_e || c == INT_E) { // exponent?
+            if (outPtr >= outBuf.length) {
+                outBuf = _textBuffer.finishCurrentSegment();
+                outPtr = 0;
+            }
+            outBuf[outPtr++] = (char) c;
+            c = _inputData.readUnsignedByte();
+            // Sign indicator?
+            if (c == '-' || c == '+') {
+                if (outPtr >= outBuf.length) {
+                    outBuf = _textBuffer.finishCurrentSegment();
+                    outPtr = 0;
+                }
+                outBuf[outPtr++] = (char) c;
+                c = _inputData.readUnsignedByte();
+            }
+            while (c <= INT_9 && c >= INT_0) {
+                ++expLen;
+                if (outPtr >= outBuf.length) {
+                    outBuf = _textBuffer.finishCurrentSegment();
+                    outPtr = 0;
+                }
+                outBuf[outPtr++] = (char) c;
+                c = _inputData.readUnsignedByte();
+            }
+            // must be followed by sequence of ints, one minimum
+            if (expLen == 0) {
+                reportUnexpectedNumberChar(c, "Exponent indicator not followed by a digit");
+            }
         }
-        return name;
-    }
 
-    /* Parsing to allow optional use of non-standard single quotes.
+        // Ok; unless we hit end-of-input, need to push last char read back
+        // As per #105, need separating space between root values; check here
+        _nextByte = c;
+        if (_parsingContext.inRoot()) {
+            _verifyRootSpace();
+        }
+        _textBuffer.setCurrentLength(outPtr);
+
+        // And there we have it!
+        return resetFloat(negative, integerPartLength, fractLen, expLen);
+    }/* Parsing to allow optional use of non-standard single quotes.
      * Plenty of duplicated code;
      * main reason being to try to avoid slowing down fast path
      * for valid JSON -- more alternatives, more code, generally
@@ -1643,410 +1984,246 @@ public class UTF8DataInputJsonParser
             name = addName(quads, qlen, currQuadBytes);
         }
         return name;
-    }
-
-    /*
-    /**********************************************************
-    /* Internal methods, symbol (name) handling
-    /**********************************************************
-     */
-
-    private final String findName(int q1, int lastQuadBytes) throws JsonParseException
-    {
-        q1 = pad(q1, lastQuadBytes);
-        // Usually we'll find it from the canonical symbol table already
-        String name = _symbols.findName(q1);
-        if (name != null) {
-            return name;
-        }
-        // If not, more work. We'll need add stuff to buffer
-        _quadBuffer[0] = q1;
-        return addName(_quadBuffer, 1, lastQuadBytes);
-    }
-
-    private final String findName(int q1, int q2, int lastQuadBytes) throws JsonParseException
-    {
-        q2 = pad(q2, lastQuadBytes);
-        // Usually we'll find it from the canonical symbol table already
-        String name = _symbols.findName(q1, q2);
-        if (name != null) {
-            return name;
-        }
-        // If not, more work. We'll need add stuff to buffer
-        _quadBuffer[0] = q1;
-        _quadBuffer[1] = q2;
-        return addName(_quadBuffer, 2, lastQuadBytes);
-    }
-
-    private final String findName(int q1, int q2, int q3, int lastQuadBytes) throws JsonParseException
-    {
-        q3 = pad(q3, lastQuadBytes);
-        String name = _symbols.findName(q1, q2, q3);
-        if (name != null) {
-            return name;
-        }
-        int[] quads = _quadBuffer;
-        quads[0] = q1;
-        quads[1] = q2;
-        quads[2] = pad(q3, lastQuadBytes);
-        return addName(quads, 3, lastQuadBytes);
-    }
-    
-    private final String findName(int[] quads, int qlen, int lastQuad, int lastQuadBytes) throws JsonParseException
-    {
-        if (qlen >= quads.length) {
-            _quadBuffer = quads = _growArrayBy(quads, quads.length);
-        }
-        quads[qlen++] = pad(lastQuad, lastQuadBytes);
-        String name = _symbols.findName(quads, qlen);
-        if (name == null) {
-            return addName(quads, qlen, lastQuadBytes);
-        }
-        return name;
-    }
-
-    /**
-     * This is the main workhorse method used when we take a symbol
-     * table miss. It needs to demultiplex individual bytes, decode
-     * multi-byte chars (if any), and then construct Name instance
-     * and add it to the symbol table.
-     */
-    private final String addName(int[] quads, int qlen, int lastQuadBytes) throws JsonParseException
+    }private final JsonToken _nextTokenNotInObject(int i) throws IOException
     {
-        /* Ok: must decode UTF-8 chars. No other validation is
-         * needed, since unescaping has been done earlier as necessary
-         * (as well as error reporting for unescaped control chars)
-         */
-        // 4 bytes per quad, except last one maybe less
-        int byteLen = (qlen << 2) - 4 + lastQuadBytes;
-
-        /* And last one is not correctly aligned (leading zero bytes instead
-         * need to shift a bit, instead of trailing). Only need to shift it
-         * for UTF-8 decoding; need revert for storage (since key will not
-         * be aligned, to optimize lookup speed)
-         */
-        int lastQuad;
-
-        if (lastQuadBytes < 4) {
-            lastQuad = quads[qlen-1];
-            // 8/16/24 bit left shift
-            quads[qlen-1] = (lastQuad << ((4 - lastQuadBytes) << 3));
-        } else {
-            lastQuad = 0;
-        }
-
-        // Need some working space, TextBuffer works well:
-        char[] cbuf = _textBuffer.emptyAndGetCurrentSegment();
-        int cix = 0;
-
-        for (int ix = 0; ix < byteLen; ) {
-            int ch = quads[ix >> 2]; // current quad, need to shift+mask
-            int byteIx = (ix & 3);
-            ch = (ch >> ((3 - byteIx) << 3)) & 0xFF;
-            ++ix;
-
-            if (ch > 127) { // multi-byte
-                int needed;
-                if ((ch & 0xE0) == 0xC0) { // 2 bytes (0x0080 - 0x07FF)
-                    ch &= 0x1F;
-                    needed = 1;
-                } else if ((ch & 0xF0) == 0xE0) { // 3 bytes (0x0800 - 0xFFFF)
-                    ch &= 0x0F;
-                    needed = 2;
-                } else if ((ch & 0xF8) == 0xF0) { // 4 bytes; double-char with surrogates and all...
-                    ch &= 0x07;
-                    needed = 3;
-                } else { // 5- and 6-byte chars not valid xml chars
-                    _reportInvalidInitial(ch);
-                    needed = ch = 1; // never really gets this far
-                }
-                if ((ix + needed) > byteLen) {
-                    _reportInvalidEOF(" in field name", JsonToken.FIELD_NAME);
-                }
-                
-                // Ok, always need at least one more:
-                int ch2 = quads[ix >> 2]; // current quad, need to shift+mask
-                byteIx = (ix & 3);
-                ch2 = (ch2 >> ((3 - byteIx) << 3));
-                ++ix;
-                
-                if ((ch2 & 0xC0) != 0x080) {
-                    _reportInvalidOther(ch2);
-                }
-                ch = (ch << 6) | (ch2 & 0x3F);
-                if (needed > 1) {
-                    ch2 = quads[ix >> 2];
-                    byteIx = (ix & 3);
-                    ch2 = (ch2 >> ((3 - byteIx) << 3));
-                    ++ix;
-                    
-                    if ((ch2 & 0xC0) != 0x080) {
-                        _reportInvalidOther(ch2);
-                    }
-                    ch = (ch << 6) | (ch2 & 0x3F);
-                    if (needed > 2) { // 4 bytes? (need surrogates on output)
-                        ch2 = quads[ix >> 2];
-                        byteIx = (ix & 3);
-                        ch2 = (ch2 >> ((3 - byteIx) << 3));
-                        ++ix;
-                        if ((ch2 & 0xC0) != 0x080) {
-                            _reportInvalidOther(ch2 & 0xFF);
-                        }
-                        ch = (ch << 6) | (ch2 & 0x3F);
-                    }
-                }
-                if (needed > 2) { // surrogate pair? once again, let's output one here, one later on
-                    ch -= 0x10000; // to normalize it starting with 0x0
-                    if (cix >= cbuf.length) {
-                        cbuf = _textBuffer.expandCurrentSegment();
-                    }
-                    cbuf[cix++] = (char) (0xD800 + (ch >> 10));
-                    ch = 0xDC00 | (ch & 0x03FF);
-                }
-            }
-            if (cix >= cbuf.length) {
-                cbuf = _textBuffer.expandCurrentSegment();
-            }
-            cbuf[cix++] = (char) ch;
-        }
-
-        // Ok. Now we have the character array, and can construct the String
-        String baseName = new String(cbuf, 0, cix);
-        // And finally, un-align if necessary
-        if (lastQuadBytes < 4) {
-            quads[qlen-1] = lastQuad;
+        if (i == INT_QUOTE) {
+            _tokenIncomplete = true;
+            return (_currToken = JsonToken.VALUE_STRING);
         }
-        return _symbols.addName(baseName, quads, qlen);
-    }
-
-    /*
-    /**********************************************************
-    /* Internal methods, String value parsing
-    /**********************************************************
-     */
-
-    @Override
-    protected void _finishString() throws IOException
+        switch (i) {
+        case '[':
+            _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            return (_currToken = JsonToken.START_ARRAY);
+        case '{':
+            _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            return (_currToken = JsonToken.START_OBJECT);
+        case 't':
+            _matchToken("true", 1);
+            return (_currToken = JsonToken.VALUE_TRUE);
+        case 'f':
+            _matchToken("false", 1);
+            return (_currToken = JsonToken.VALUE_FALSE);
+        case 'n':
+            _matchToken("null", 1);
+            return (_currToken = JsonToken.VALUE_NULL);
+        case '-':
+            return (_currToken = _parseNegNumber());
+            /* Should we have separate handling for plus? Although
+             * it is not allowed per se, it may be erroneously used,
+             * and could be indicated by a more specific error message.
+             */
+        case '0':
+        case '1':
+        case '2':
+        case '3':
+        case '4':
+        case '5':
+        case '6':
+        case '7':
+        case '8':
+        case '9':
+            return (_currToken = _parsePosNumber(i));
+        }
+        return (_currToken = _handleUnexpectedValue(i));
+    }private final JsonToken _nextAfterName()
     {
-        int outPtr = 0;
-        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
-        final int[] codes = _icUTF8;
-        final int outEnd = outBuf.length;
-
-        do {
-            int c = _inputData.readUnsignedByte();
-            if (codes[c] != 0) {
-                if (c == INT_QUOTE) {
-                    _textBuffer.setCurrentLength(outPtr);
-                    return;
-                }
-                _finishString2(outBuf, outPtr, c);
-                return;
-            }
-            outBuf[outPtr++] = (char) c;
-        } while (outPtr < outEnd);
-        _finishString2(outBuf, outPtr, _inputData.readUnsignedByte());
-    }
+        _nameCopied = false; // need to invalidate if it was copied
+        JsonToken t = _nextToken;
+        _nextToken = null;
 
-    private String _finishAndReturnString() throws IOException
+        // Also: may need to start new context?
+        if (t == JsonToken.START_ARRAY) {
+            _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+        } else if (t == JsonToken.START_OBJECT) {
+            _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+        }
+        return (_currToken = t);
+    }protected final void _matchToken(String matchStr, int i) throws IOException
     {
-        int outPtr = 0;
-        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
-        final int[] codes = _icUTF8;
-        final int outEnd = outBuf.length;
-
+        final int len = matchStr.length();
         do {
-            int c = _inputData.readUnsignedByte();
-            if (codes[c] != 0) {
-                if (c == INT_QUOTE) {
-                    return _textBuffer.setCurrentAndReturn(outPtr);
-                }
-                _finishString2(outBuf, outPtr, c);
-                return _textBuffer.contentsAsString();
+            int ch = _inputData.readUnsignedByte();
+            if (ch != matchStr.charAt(i)) {
+                _reportInvalidToken(ch, matchStr.substring(0, i));
             }
-            outBuf[outPtr++] = (char) c;
-        } while (outPtr < outEnd);
-        _finishString2(outBuf, outPtr, _inputData.readUnsignedByte());
-        return _textBuffer.contentsAsString();
-    }
-    
-    private final void _finishString2(char[] outBuf, int outPtr, int c)
+        } while (++i < len);
+
+        int ch = _inputData.readUnsignedByte();
+        if (ch >= '0' && ch != ']' && ch != '}') { // expected/allowed chars
+            _checkMatchEnd(matchStr, i, ch);
+        }
+        _nextByte = ch;
+    } /**
+     * Method for handling cases where first non-space character
+     * of an expected value token is not legal for standard JSON content.
+     */
+    protected JsonToken _handleUnexpectedValue(int c)
         throws IOException
     {
-        // Here we do want to do full decoding, hence:
-        final int[] codes = _icUTF8;
-        int outEnd = outBuf.length;
-
-        main_loop:
-        for (;; c = _inputData.readUnsignedByte()) {
-            // Then the tight ASCII non-funny-char loop:
-            while (codes[c] == 0) {
-                if (outPtr >= outEnd) {
-                    outBuf = _textBuffer.finishCurrentSegment();
-                    outPtr = 0;
-                    outEnd = outBuf.length;
-                }
-                outBuf[outPtr++] = (char) c;
-                c = _inputData.readUnsignedByte();
+        // Most likely an error, unless we are to allow single-quote-strings
+        switch (c) {
+        case ']':
+            if (!_parsingContext.inArray()) {
+                break;
             }
-            // Ok: end marker, escape or multi-byte?
-            if (c == INT_QUOTE) {
-                break main_loop;
+            // fall through
+        case ',':
+            /* !!! TODO: 08-May-2016, tatu: To support `Feature.ALLOW_MISSING_VALUES` would
+             *    need handling here...
+             */
+            if (isEnabled(Feature.ALLOW_MISSING_VALUES)) {
+//               _inputPtr--;
+                _nextByte = c;
+               return JsonToken.VALUE_NULL;
             }
-            switch (codes[c]) {
-            case 1: // backslash
-                c = _decodeEscaped();
-                break;
-            case 2: // 2-byte UTF
-                c = _decodeUtf8_2(c);
-                break;
-            case 3: // 3-byte UTF
-                c = _decodeUtf8_3(c);
-                break;
-            case 4: // 4-byte UTF
-                c = _decodeUtf8_4(c);
-                // Let's add first part right away:
-                outBuf[outPtr++] = (char) (0xD800 | (c >> 10));
-                if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
-                    outPtr = 0;
-                    outEnd = outBuf.length;
-                }
-                c = 0xDC00 | (c & 0x3FF);
-                // And let the other char output down below
-                break;
-            default:
-                if (c < INT_SPACE) {
-                    _throwUnquotedSpace(c, "string value");
-                } else {
-                    // Is this good enough error message?
-                    _reportInvalidChar(c);
-                }
+            // fall through
+        case '}':
+            // Error: neither is valid at this point; valid closers have
+            // been handled earlier
+            _reportUnexpectedChar(c, "expected a value");
+        case '\'':
+            if (isEnabled(Feature.ALLOW_SINGLE_QUOTES)) {
+                return _handleApos();
             }
-            // Need more room?
-            if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
-                outPtr = 0;
-                outEnd = outBuf.length;
+            break;
+        case 'N':
+            _matchToken("NaN", 1);
+            if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
+                return resetAsNaN("NaN", Double.NaN);
             }
-            // Ok, let's add char to output:
-            outBuf[outPtr++] = (char) c;
+            _reportError("Non-standard token 'NaN': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
+            break;
+        case 'I':
+            _matchToken("Infinity", 1);
+            if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
+                return resetAsNaN("Infinity", Double.POSITIVE_INFINITY);
+            }
+            _reportError("Non-standard token 'Infinity': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
+            break;
+        case '+': // note: '-' is taken as number
+            return _handleInvalidNumberStart(_inputData.readUnsignedByte(), false);
         }
-        _textBuffer.setCurrentLength(outPtr);
-    }
-
-    /**
-     * Method called to skim through rest of unparsed String value,
-     * if it is not needed. This can be done bit faster if contents
-     * need not be stored for future access.
+        // [core#77] Try to decode most likely token
+        if (Character.isJavaIdentifierStart(c)) {
+            _reportInvalidToken(c, ""+((char) c), "('true', 'false' or 'null')");
+        }
+        // but if it doesn't look like a token:
+        _reportUnexpectedChar(c, "expected a valid value (number, String, array, object, 'true', 'false' or 'null')");
+        return null;
+    } /**
+     * Method called when we see non-white space character other
+     * than double quote, when expecting a field name.
+     * In standard mode will just throw an exception; but
+     * in non-standard modes may be able to parse name.
      */
-    protected void _skipString() throws IOException
+    protected String _handleOddName(int ch) throws IOException
     {
-        _tokenIncomplete = false;
+        if (ch == '\'' && isEnabled(Feature.ALLOW_SINGLE_QUOTES)) {
+            return _parseAposName();
+        }
+        if (!isEnabled(Feature.ALLOW_UNQUOTED_FIELD_NAMES)) {
+            char c = (char) _decodeCharForError(ch);
+            _reportUnexpectedChar(c, "was expecting double-quote to start field name");
+        }
+        /* Also: note that although we use a different table here,
+         * it does NOT handle UTF-8 decoding. It'll just pass those
+         * high-bit codes as acceptable for later decoding.
+         */
+        final int[] codes = CharTypes.getInputCodeUtf8JsNames();
+        // Also: must start with a valid character...
+        if (codes[ch] != 0) {
+            _reportUnexpectedChar(ch, "was expecting either valid name character (for unquoted name) or double-quote (for quoted) to start field name");
+        }
 
-        // Need to be fully UTF-8 aware here:
-        final int[] codes = _icUTF8;
+        /* Ok, now; instead of ultra-optimizing parsing here (as with
+         * regular JSON names), let's just use the generic "slow"
+         * variant. Can measure its impact later on if need be
+         */
+        int[] quads = _quadBuffer;
+        int qlen = 0;
+        int currQuad = 0;
+        int currQuadBytes = 0;
 
-        main_loop:
         while (true) {
-            int c;
-
-            ascii_loop:
-            while (true) {
-                c = _inputData.readUnsignedByte();
-                if (codes[c] != 0) {
-                    break ascii_loop;
+            // Ok, we have one more byte to add at any rate:
+            if (currQuadBytes < 4) {
+                ++currQuadBytes;
+                currQuad = (currQuad << 8) | ch;
+            } else {
+                if (qlen >= quads.length) {
+                    _quadBuffer = quads = _growArrayBy(quads, quads.length);
                 }
+                quads[qlen++] = currQuad;
+                currQuad = ch;
+                currQuadBytes = 1;
             }
-            // Ok: end marker, escape or multi-byte?
-            if (c == INT_QUOTE) {
-                break main_loop;
-            }
-            
-            switch (codes[c]) {
-            case 1: // backslash
-                _decodeEscaped();
-                break;
-            case 2: // 2-byte UTF
-                _skipUtf8_2();
-                break;
-            case 3: // 3-byte UTF
-                _skipUtf8_3();
-                break;
-            case 4: // 4-byte UTF
-                _skipUtf8_4();
+            ch = _inputData.readUnsignedByte();
+            if (codes[ch] != 0) {
                 break;
-            default:
-                if (c < INT_SPACE) {
-                    _throwUnquotedSpace(c, "string value");
-                } else {
-                    // Is this good enough error message?
-                    _reportInvalidChar(c);
-                }
             }
         }
-    }
-
-    /**
-     * Method for handling cases where first non-space character
-     * of an expected value token is not legal for standard JSON content.
+        // Note: we must "push back" character read here for future consumption
+        _nextByte = ch;
+        if (currQuadBytes > 0) {
+            if (qlen >= quads.length) {
+                _quadBuffer = quads = _growArrayBy(quads, quads.length);
+            }
+            quads[qlen++] = currQuad;
+        }
+        String name = _symbols.findName(quads, qlen);
+        if (name == null) {
+            name = addName(quads, qlen, currQuadBytes);
+        }
+        return name;
+    } /**
+     * Method called when we have seen one zero, and want to ensure
+     * it is not followed by another, or, if leading zeroes allowed,
+     * skipped redundant ones.
+     *
+     * @return Character immediately following zeroes
      */
-    protected JsonToken _handleUnexpectedValue(int c)
+    private final int _handleLeadingZeroes() throws IOException
+    {
+        int ch = _inputData.readUnsignedByte();
+        // if not followed by a number (probably '.'); return zero as is, to be included
+        if (ch < INT_0 || ch > INT_9) {
+            return ch;
+        }
+        // we may want to allow leading zeroes them, after all...
+        if (!isEnabled(Feature.ALLOW_NUMERIC_LEADING_ZEROS)) {
+            reportInvalidNumber("Leading zeroes not allowed");
+        }
+        // if so, just need to skip either all zeroes (if followed by number); or all but one (if non-number)
+        while (ch == INT_0) {
+            ch = _inputData.readUnsignedByte();
+        }
+        return ch;
+    } /**
+     * Method called if expected numeric value (due to leading sign) does not
+     * look like a number
+     */
+    protected JsonToken _handleInvalidNumberStart(int ch, boolean neg)
         throws IOException
     {
-        // Most likely an error, unless we are to allow single-quote-strings
-        switch (c) {
-        case ']':
-            if (!_parsingContext.inArray()) {
+        while (ch == 'I') {
+            ch = _inputData.readUnsignedByte();
+            String match;
+            if (ch == 'N') {
+                match = neg ? "-INF" :"+INF";
+            } else if (ch == 'n') {
+                match = neg ? "-Infinity" :"+Infinity";
+            } else {
                 break;
             }
-            // fall through
-        case ',':
-            /* !!! TODO: 08-May-2016, tatu: To support `Feature.ALLOW_MISSING_VALUES` would
-             *    need handling here...
-             */
-            if (isEnabled(Feature.ALLOW_MISSING_VALUES)) {
-//               _inputPtr--;
-                _nextByte = c;
-               return JsonToken.VALUE_NULL;
-            }
-            // fall through
-        case '}':
-            // Error: neither is valid at this point; valid closers have
-            // been handled earlier
-            _reportUnexpectedChar(c, "expected a value");
-        case '\'':
-            if (isEnabled(Feature.ALLOW_SINGLE_QUOTES)) {
-                return _handleApos();
-            }
-            break;
-        case 'N':
-            _matchToken("NaN", 1);
-            if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
-                return resetAsNaN("NaN", Double.NaN);
-            }
-            _reportError("Non-standard token 'NaN': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
-            break;
-        case 'I':
-            _matchToken("Infinity", 1);
+            _matchToken(match, 3);
             if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
-                return resetAsNaN("Infinity", Double.POSITIVE_INFINITY);
+                return resetAsNaN(match, neg ? Double.NEGATIVE_INFINITY : Double.POSITIVE_INFINITY);
             }
-            _reportError("Non-standard token 'Infinity': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
-            break;
-        case '+': // note: '-' is taken as number
-            return _handleInvalidNumberStart(_inputData.readUnsignedByte(), false);
-        }
-        // [core#77] Try to decode most likely token
-        if (Character.isJavaIdentifierStart(c)) {
-            _reportInvalidToken(c, ""+((char) c), "('true', 'false' or 'null')");
+            _reportError("Non-standard token '"+match+"': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
         }
-        // but if it doesn't look like a token:
-        _reportUnexpectedChar(c, "expected a valid value (number, String, array, object, 'true', 'false' or 'null')");
+        reportUnexpectedNumberChar(ch, "expected digit (0-9) to follow minus sign, for valid numeric value");
         return null;
-    }
-
-    protected JsonToken _handleApos() throws IOException
+    }protected JsonToken _handleApos() throws IOException
     {
         int c = 0;
         // Otherwise almost verbatim copy of _finishString()
@@ -2087,375 +2264,210 @@ public class UTF8DataInputJsonParser
                 break;
             case 3: // 3-byte UTF
                 c = _decodeUtf8_3(c);
-                break;
-            case 4: // 4-byte UTF
-                c = _decodeUtf8_4(c);
-                // Let's add first part right away:
-                outBuf[outPtr++] = (char) (0xD800 | (c >> 10));
-                if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
-                    outPtr = 0;
-                }
-                c = 0xDC00 | (c & 0x3FF);
-                // And let the other char output down below
-                break;
-            default:
-                if (c < INT_SPACE) {
-                    _throwUnquotedSpace(c, "string value");
-                }
-                // Is this good enough error message?
-                _reportInvalidChar(c);
-            }
-            // Need more room?
-            if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
-                outPtr = 0;
-            }
-            // Ok, let's add char to output:
-            outBuf[outPtr++] = (char) c;
-        }
-        _textBuffer.setCurrentLength(outPtr);
-
-        return JsonToken.VALUE_STRING;
-    }
-    
-    /**
-     * Method called if expected numeric value (due to leading sign) does not
-     * look like a number
-     */
-    protected JsonToken _handleInvalidNumberStart(int ch, boolean neg)
-        throws IOException
-    {
-        while (ch == 'I') {
-            ch = _inputData.readUnsignedByte();
-            String match;
-            if (ch == 'N') {
-                match = neg ? "-INF" :"+INF";
-            } else if (ch == 'n') {
-                match = neg ? "-Infinity" :"+Infinity";
-            } else {
-                break;
-            }
-            _matchToken(match, 3);
-            if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
-                return resetAsNaN(match, neg ? Double.NEGATIVE_INFINITY : Double.POSITIVE_INFINITY);
-            }
-            _reportError("Non-standard token '"+match+"': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
-        }
-        reportUnexpectedNumberChar(ch, "expected digit (0-9) to follow minus sign, for valid numeric value");
-        return null;
-    }
-
-    protected final void _matchToken(String matchStr, int i) throws IOException
-    {
-        final int len = matchStr.length();
-        do {
-            int ch = _inputData.readUnsignedByte();
-            if (ch != matchStr.charAt(i)) {
-                _reportInvalidToken(ch, matchStr.substring(0, i));
-            }
-        } while (++i < len);
-
-        int ch = _inputData.readUnsignedByte();
-        if (ch >= '0' && ch != ']' && ch != '}') { // expected/allowed chars
-            _checkMatchEnd(matchStr, i, ch);
-        }
-        _nextByte = ch;
-    }
-
-    private final void _checkMatchEnd(String matchStr, int i, int ch) throws IOException {
-        // but actually only alphanums are problematic
-        char c = (char) _decodeCharForError(ch);
-        if (Character.isJavaIdentifierPart(c)) {
-            _reportInvalidToken(c, matchStr.substring(0, i));
-        }
-    }
-
-    /*
-    /**********************************************************
-    /* Internal methods, ws skipping, escape/unescape
-    /**********************************************************
-     */
-
-    private final int _skipWS() throws IOException
-    {
-        int i = _nextByte;
-        if (i < 0) {
-            i = _inputData.readUnsignedByte();
-        } else {
-            _nextByte = -1;
-        }
-        while (true) {
-            if (i > INT_SPACE) {
-                if (i == INT_SLASH || i == INT_HASH) {
-                    return _skipWSComment(i);
-                }
-                return i;
-            } else {
-                // 06-May-2016, tatu: Could verify validity of WS, but for now why bother.
-                //   ... but line number is useful thingy
-                if (i == INT_CR || i == INT_LF) {
-                    ++_currInputRow;
-                }
-            }
-            i = _inputData.readUnsignedByte();
-        }
-    }
-
-    /**
-     * Alternative to {@link #_skipWS} that handles possible {@link EOFException}
-     * caused by trying to read past the end of {@link InputData}.
-     *
-     * @since 2.9
-     */
-    private final int _skipWSOrEnd() throws IOException
-    {
-        int i = _nextByte;
-        if (i < 0) {
-            try {
-                i = _inputData.readUnsignedByte();
-            } catch (EOFException e) {
-                return _eofAsNextChar();
-            }
-        } else {
-            _nextByte = -1;
-        }
-        while (true) {
-            if (i > INT_SPACE) {
-                if (i == INT_SLASH || i == INT_HASH) {
-                    return _skipWSComment(i);
-                }
-                return i;
-            } else {
-                // 06-May-2016, tatu: Could verify validity of WS, but for now why bother.
-                //   ... but line number is useful thingy
-                if (i == INT_CR || i == INT_LF) {
-                    ++_currInputRow;
-                }
-            }
-            try {
-                i = _inputData.readUnsignedByte();
-            } catch (EOFException e) {
-                return _eofAsNextChar();
-            }
-        }
-    }
-    
-    private final int _skipWSComment(int i) throws IOException
-    {
-        while (true) {
-            if (i > INT_SPACE) {
-                if (i == INT_SLASH) {
-                    _skipComment();
-                } else if (i == INT_HASH) {
-                    if (!_skipYAMLComment()) {
-                        return i;
-                    }
-                } else {
-                    return i;
-                }
-            } else {
-                // 06-May-2016, tatu: Could verify validity of WS, but for now why bother.
-                //   ... but line number is useful thingy
-                if (i == INT_CR || i == INT_LF) {
-                    ++_currInputRow;
+                break;
+            case 4: // 4-byte UTF
+                c = _decodeUtf8_4(c);
+                // Let's add first part right away:
+                outBuf[outPtr++] = (char) (0xD800 | (c >> 10));
+                if (outPtr >= outBuf.length) {
+                    outBuf = _textBuffer.finishCurrentSegment();
+                    outPtr = 0;
                 }
-                /*
-                if ((i != INT_SPACE) && (i != INT_LF) && (i != INT_CR)) {
-                    _throwInvalidSpace(i);
+                c = 0xDC00 | (c & 0x3FF);
+                // And let the other char output down below
+                break;
+            default:
+                if (c < INT_SPACE) {
+                    _throwUnquotedSpace(c, "string value");
                 }
-                */
+                // Is this good enough error message?
+                _reportInvalidChar(c);
             }
-            i = _inputData.readUnsignedByte();
-        }        
-    }
+            // Need more room?
+            if (outPtr >= outBuf.length) {
+                outBuf = _textBuffer.finishCurrentSegment();
+                outPtr = 0;
+            }
+            // Ok, let's add char to output:
+            outBuf[outPtr++] = (char) c;
+        }
+        _textBuffer.setCurrentLength(outPtr);
 
-    private final int _skipColon() throws IOException
+        return JsonToken.VALUE_STRING;
+    }private static int[] _growArrayBy(int[] arr, int more)
     {
-        int i = _nextByte;
-        if (i < 0) {
-            i = _inputData.readUnsignedByte();
-        } else {
-            _nextByte = -1;
+        if (arr == null) {
+            return new int[more];
         }
-        // Fast path: colon with optional single-space/tab before and/or after:
-        if (i == INT_COLON) { // common case, no leading space
-            i = _inputData.readUnsignedByte();
-            if (i > INT_SPACE) { // nor trailing
-                if (i == INT_SLASH || i == INT_HASH) {
-                    return _skipColon2(i, true);
-                }
-                return i;
-            }
-            if (i == INT_SPACE || i == INT_TAB) {
-                i = _inputData.readUnsignedByte();
-                if (i > INT_SPACE) {
-                    if (i == INT_SLASH || i == INT_HASH) {
-                        return _skipColon2(i, true);
-                    }
-                    return i;
-                }
-            }
-            return _skipColon2(i, true); // true -> skipped colon
+        return Arrays.copyOf(arr, arr.length + more);
+    }protected final String _getText2(JsonToken t)
+    {
+        if (t == null) {
+            return null;
         }
-        if (i == INT_SPACE || i == INT_TAB) {
-            i = _inputData.readUnsignedByte();
+        switch (t.id()) {
+        case ID_FIELD_NAME:
+            return _parsingContext.getCurrentName();
+
+        case ID_STRING:
+            // fall through
+        case ID_NUMBER_INT:
+        case ID_NUMBER_FLOAT:
+            return _textBuffer.contentsAsString();
+        default:
+        	return t.asString();
         }
-        if (i == INT_COLON) {
-            i = _inputData.readUnsignedByte();
-            if (i > INT_SPACE) {
-                if (i == INT_SLASH || i == INT_HASH) {
-                    return _skipColon2(i, true);
+    }private final void _finishString2(char[] outBuf, int outPtr, int c)
+        throws IOException
+    {
+        // Here we do want to do full decoding, hence:
+        final int[] codes = _icUTF8;
+        int outEnd = outBuf.length;
+
+        main_loop:
+        for (;; c = _inputData.readUnsignedByte()) {
+            // Then the tight ASCII non-funny-char loop:
+            while (codes[c] == 0) {
+                if (outPtr >= outEnd) {
+                    outBuf = _textBuffer.finishCurrentSegment();
+                    outPtr = 0;
+                    outEnd = outBuf.length;
                 }
-                return i;
+                outBuf[outPtr++] = (char) c;
+                c = _inputData.readUnsignedByte();
             }
-            if (i == INT_SPACE || i == INT_TAB) {
-                i = _inputData.readUnsignedByte();
-                if (i > INT_SPACE) {
-                    if (i == INT_SLASH || i == INT_HASH) {
-                        return _skipColon2(i, true);
-                    }
-                    return i;
-                }
+            // Ok: end marker, escape or multi-byte?
+            if (c == INT_QUOTE) {
+                break main_loop;
             }
-            return _skipColon2(i, true);
-        }
-        return _skipColon2(i, false);
-    }
-
-    private final int _skipColon2(int i, boolean gotColon) throws IOException
-    {
-        for (;; i = _inputData.readUnsignedByte()) {
-            if (i > INT_SPACE) {
-                if (i == INT_SLASH) {
-                    _skipComment();
-                    continue;
-                }
-                if (i == INT_HASH) {
-                    if (_skipYAMLComment()) {
-                        continue;
-                    }
-                }
-                if (gotColon) {
-                    return i;
-                }
-                if (i != INT_COLON) {
-                    _reportUnexpectedChar(i, "was expecting a colon to separate field name and value");
+            switch (codes[c]) {
+            case 1: // backslash
+                c = _decodeEscaped();
+                break;
+            case 2: // 2-byte UTF
+                c = _decodeUtf8_2(c);
+                break;
+            case 3: // 3-byte UTF
+                c = _decodeUtf8_3(c);
+                break;
+            case 4: // 4-byte UTF
+                c = _decodeUtf8_4(c);
+                // Let's add first part right away:
+                outBuf[outPtr++] = (char) (0xD800 | (c >> 10));
+                if (outPtr >= outBuf.length) {
+                    outBuf = _textBuffer.finishCurrentSegment();
+                    outPtr = 0;
+                    outEnd = outBuf.length;
                 }
-                gotColon = true;
-            } else {
-                // 06-May-2016, tatu: Could verify validity of WS, but for now why bother.
-                //   ... but line number is useful thingy
-                if (i == INT_CR || i == INT_LF) {
-                    ++_currInputRow;
+                c = 0xDC00 | (c & 0x3FF);
+                // And let the other char output down below
+                break;
+            default:
+                if (c < INT_SPACE) {
+                    _throwUnquotedSpace(c, "string value");
+                } else {
+                    // Is this good enough error message?
+                    _reportInvalidChar(c);
                 }
             }
+            // Need more room?
+            if (outPtr >= outBuf.length) {
+                outBuf = _textBuffer.finishCurrentSegment();
+                outPtr = 0;
+                outEnd = outBuf.length;
+            }
+            // Ok, let's add char to output:
+            outBuf[outPtr++] = (char) c;
         }
-    }
-
-    private final void _skipComment() throws IOException
+        _textBuffer.setCurrentLength(outPtr);
+    }@Override
+    protected void _finishString() throws IOException
     {
-        if (!isEnabled(Feature.ALLOW_COMMENTS)) {
-            _reportUnexpectedChar('/', "maybe a (non-standard) comment? (not recognized as one since Feature 'ALLOW_COMMENTS' not enabled for parser)");
-        }
-        int c = _inputData.readUnsignedByte();
-        if (c == '/') {
-            _skipLine();
-        } else if (c == '*') {
-            _skipCComment();
-        } else {
-            _reportUnexpectedChar(c, "was expecting either '*' or '/' for a comment");
-        }
-    }
+        int outPtr = 0;
+        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
+        final int[] codes = _icUTF8;
+        final int outEnd = outBuf.length;
 
-    private final void _skipCComment() throws IOException
+        do {
+            int c = _inputData.readUnsignedByte();
+            if (codes[c] != 0) {
+                if (c == INT_QUOTE) {
+                    _textBuffer.setCurrentLength(outPtr);
+                    return;
+                }
+                _finishString2(outBuf, outPtr, c);
+                return;
+            }
+            outBuf[outPtr++] = (char) c;
+        } while (outPtr < outEnd);
+        _finishString2(outBuf, outPtr, _inputData.readUnsignedByte());
+    }private String _finishAndReturnString() throws IOException
     {
-        // Need to be UTF-8 aware here to decode content (for skipping)
-        final int[] codes = CharTypes.getInputCodeComment();
-        int i = _inputData.readUnsignedByte();
+        int outPtr = 0;
+        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
+        final int[] codes = _icUTF8;
+        final int outEnd = outBuf.length;
 
-        // Ok: need the matching '*/'
-        main_loop:
-        while (true) {
-            int code = codes[i];
-            if (code != 0) {
-                switch (code) {
-                case '*':
-                    i = _inputData.readUnsignedByte();
-                    if (i == INT_SLASH) {
-                        return;
-                    }
-                    continue main_loop;
-                case INT_LF:
-                case INT_CR:
-                    ++_currInputRow;
-                    break;
-                case 2: // 2-byte UTF
-                    _skipUtf8_2();
-                    break;
-                case 3: // 3-byte UTF
-                    _skipUtf8_3();
-                    break;
-                case 4: // 4-byte UTF
-                    _skipUtf8_4();
-                    break;
-                default: // e.g. -1
-                    // Is this good enough error message?
-                    _reportInvalidChar(i);
+        do {
+            int c = _inputData.readUnsignedByte();
+            if (codes[c] != 0) {
+                if (c == INT_QUOTE) {
+                    return _textBuffer.setCurrentAndReturn(outPtr);
                 }
+                _finishString2(outBuf, outPtr, c);
+                return _textBuffer.contentsAsString();
             }
-            i = _inputData.readUnsignedByte();
+            outBuf[outPtr++] = (char) c;
+        } while (outPtr < outEnd);
+        _finishString2(outBuf, outPtr, _inputData.readUnsignedByte());
+        return _textBuffer.contentsAsString();
+    } /**
+     * @return Character value <b>minus 0x10000</c>; this so that caller
+     *    can readily expand it to actual surrogates
+     */
+    private final int _decodeUtf8_4(int c) throws IOException
+    {
+        int d = _inputData.readUnsignedByte();
+        if ((d & 0xC0) != 0x080) {
+            _reportInvalidOther(d & 0xFF);
+        }
+        c = ((c & 0x07) << 6) | (d & 0x3F);
+        d = _inputData.readUnsignedByte();
+        if ((d & 0xC0) != 0x080) {
+            _reportInvalidOther(d & 0xFF);
+        }
+        c = (c << 6) | (d & 0x3F);
+        d = _inputData.readUnsignedByte();
+        if ((d & 0xC0) != 0x080) {
+            _reportInvalidOther(d & 0xFF);
         }
-    }
 
-    private final boolean _skipYAMLComment() throws IOException
+        /* note: won't change it to negative here, since caller
+         * already knows it'll need a surrogate
+         */
+        return ((c << 6) | (d & 0x3F)) - 0x10000;
+    }private final int _decodeUtf8_3(int c1) throws IOException
     {
-        if (!isEnabled(Feature.ALLOW_YAML_COMMENTS)) {
-            return false;
+        c1 &= 0x0F;
+        int d = _inputData.readUnsignedByte();
+        if ((d & 0xC0) != 0x080) {
+            _reportInvalidOther(d & 0xFF);
         }
-        _skipLine();
-        return true;
-    }
-
-    /**
-     * Method for skipping contents of an input line; usually for CPP
-     * and YAML style comments.
-     */
-    private final void _skipLine() throws IOException
+        int c = (c1 << 6) | (d & 0x3F);
+        d = _inputData.readUnsignedByte();
+        if ((d & 0xC0) != 0x080) {
+            _reportInvalidOther(d & 0xFF);
+        }
+        c = (c << 6) | (d & 0x3F);
+        return c;
+    }private final int _decodeUtf8_2(int c) throws IOException
     {
-        // Ok: need to find EOF or linefeed
-        final int[] codes = CharTypes.getInputCodeComment();
-        while (true) {
-            int i = _inputData.readUnsignedByte();
-            int code = codes[i];
-            if (code != 0) {
-                switch (code) {
-                case INT_LF:
-                case INT_CR:
-                    ++_currInputRow;
-                    return;
-                case '*': // nop for these comments
-                    break;
-                case 2: // 2-byte UTF
-                    _skipUtf8_2();
-                    break;
-                case 3: // 3-byte UTF
-                    _skipUtf8_3();
-                    break;
-                case 4: // 4-byte UTF
-                    _skipUtf8_4();
-                    break;
-                default: // e.g. -1
-                    if (code < 0) {
-                        // Is this good enough error message?
-                        _reportInvalidChar(i);
-                    }
-                }
-            }
+        int d = _inputData.readUnsignedByte();
+        if ((d & 0xC0) != 0x080) {
+            _reportInvalidOther(d & 0xFF);
         }
-    }
-    
-    @Override
+        return ((c & 0x1F) << 6) | (d & 0x3F);
+    }@Override
     protected char _decodeEscaped() throws IOException
     {
         int c = _inputData.readUnsignedByte();
@@ -2497,14 +2509,12 @@ public class UTF8DataInputJsonParser
             value = (value << 4) | digit;
         }
         return (char) value;
-    }
-
-    protected int _decodeCharForError(int firstByte) throws IOException
+    }protected int _decodeCharForError(int firstByte) throws IOException
     {
         int c = firstByte & 0xFF;
         if (c > 0x7F) { // if >= 0, is ascii and fine as is
             int needed;
-            
+
             // Ok; if we end here, we got multi-byte combination
             if ((c & 0xE0) == 0xC0) { // 2 bytes (0x0080 - 0x07FF)
                 c &= 0x1F;
@@ -2526,7 +2536,7 @@ public class UTF8DataInputJsonParser
                 _reportInvalidOther(d & 0xFF);
             }
             c = (c << 6) | (d & 0x3F);
-            
+
             if (needed > 1) { // needed == 1 means 2 bytes total
                 d = _inputData.readUnsignedByte(); // 3rd byte
                 if ((d & 0xC0) != 0x080) {
@@ -2543,174 +2553,7 @@ public class UTF8DataInputJsonParser
             }
         }
         return c;
-    }
-
-    /*
-    /**********************************************************
-    /* Internal methods,UTF8 decoding
-    /**********************************************************
-     */
-
-    private final int _decodeUtf8_2(int c) throws IOException
-    {
-        int d = _inputData.readUnsignedByte();
-        if ((d & 0xC0) != 0x080) {
-            _reportInvalidOther(d & 0xFF);
-        }
-        return ((c & 0x1F) << 6) | (d & 0x3F);
-    }
-
-    private final int _decodeUtf8_3(int c1) throws IOException
-    {
-        c1 &= 0x0F;
-        int d = _inputData.readUnsignedByte();
-        if ((d & 0xC0) != 0x080) {
-            _reportInvalidOther(d & 0xFF);
-        }
-        int c = (c1 << 6) | (d & 0x3F);
-        d = _inputData.readUnsignedByte();
-        if ((d & 0xC0) != 0x080) {
-            _reportInvalidOther(d & 0xFF);
-        }
-        c = (c << 6) | (d & 0x3F);
-        return c;
-    }
-
-    /**
-     * @return Character value <b>minus 0x10000</c>; this so that caller
-     *    can readily expand it to actual surrogates
-     */
-    private final int _decodeUtf8_4(int c) throws IOException
-    {
-        int d = _inputData.readUnsignedByte();
-        if ((d & 0xC0) != 0x080) {
-            _reportInvalidOther(d & 0xFF);
-        }
-        c = ((c & 0x07) << 6) | (d & 0x3F);
-        d = _inputData.readUnsignedByte();
-        if ((d & 0xC0) != 0x080) {
-            _reportInvalidOther(d & 0xFF);
-        }
-        c = (c << 6) | (d & 0x3F);
-        d = _inputData.readUnsignedByte();
-        if ((d & 0xC0) != 0x080) {
-            _reportInvalidOther(d & 0xFF);
-        }
-
-        /* note: won't change it to negative here, since caller
-         * already knows it'll need a surrogate
-         */
-        return ((c << 6) | (d & 0x3F)) - 0x10000;
-    }
-
-    private final void _skipUtf8_2() throws IOException
-    {
-        int c = _inputData.readUnsignedByte();
-        if ((c & 0xC0) != 0x080) {
-            _reportInvalidOther(c & 0xFF);
-        }
-    }
-
-    /* Alas, can't heavily optimize skipping, since we still have to
-     * do validity checks...
-     */
-    private final void _skipUtf8_3() throws IOException
-    {
-        //c &= 0x0F;
-        int c = _inputData.readUnsignedByte();
-        if ((c & 0xC0) != 0x080) {
-            _reportInvalidOther(c & 0xFF);
-        }
-        c = _inputData.readUnsignedByte();
-        if ((c & 0xC0) != 0x080) {
-            _reportInvalidOther(c & 0xFF);
-        }
-    }
-
-    private final void _skipUtf8_4() throws IOException
-    {
-        int d = _inputData.readUnsignedByte();
-        if ((d & 0xC0) != 0x080) {
-            _reportInvalidOther(d & 0xFF);
-        }
-        d = _inputData.readUnsignedByte();
-        if ((d & 0xC0) != 0x080) {
-            _reportInvalidOther(d & 0xFF);
-        }
-        d = _inputData.readUnsignedByte();
-        if ((d & 0xC0) != 0x080) {
-            _reportInvalidOther(d & 0xFF);
-        }
-    }
-
-    /*
-    /**********************************************************
-    /* Internal methods, error reporting
-    /**********************************************************
-     */
-
-    protected void _reportInvalidToken(int ch, String matchedPart) throws IOException
-     {
-         _reportInvalidToken(ch, matchedPart, "'null', 'true', 'false' or NaN");
-     }
-
-    protected void _reportInvalidToken(int ch, String matchedPart, String msg)
-        throws IOException
-     {
-         StringBuilder sb = new StringBuilder(matchedPart);
-
-         /* Let's just try to find what appears to be the token, using
-          * regular Java identifier character rules. It's just a heuristic,
-          * nothing fancy here (nor fast).
-          */
-         while (true) {
-             char c = (char) _decodeCharForError(ch);
-             if (!Character.isJavaIdentifierPart(c)) {
-                 break;
-             }
-             sb.append(c);
-             ch = _inputData.readUnsignedByte();
-         }
-         _reportError("Unrecognized token '"+sb.toString()+"': was expecting "+msg);
-     }
-        
-    protected void _reportInvalidChar(int c)
-        throws JsonParseException
-    {
-        // Either invalid WS or illegal UTF-8 start char
-        if (c < INT_SPACE) {
-            _throwInvalidSpace(c);
-        }
-        _reportInvalidInitial(c);
-    }
-
-    protected void _reportInvalidInitial(int mask)
-        throws JsonParseException
-    {
-        _reportError("Invalid UTF-8 start byte 0x"+Integer.toHexString(mask));
-    }
-
-    private void _reportInvalidOther(int mask)
-        throws JsonParseException
-    {
-        _reportError("Invalid UTF-8 middle byte 0x"+Integer.toHexString(mask));
-    }
-
-    private static int[] _growArrayBy(int[] arr, int more)
-    {
-        if (arr == null) {
-            return new int[more];
-        }
-        return Arrays.copyOf(arr, arr.length + more);
-    }
-
-    /*
-    /**********************************************************
-    /* Internal methods, binary access
-    /**********************************************************
-     */
-
-    /**
+    } /**
      * Efficient handling for incremental parsing of base64-encoded
      * textual content.
      */
@@ -2737,7 +2580,7 @@ public class UTF8DataInputJsonParser
                 }
             }
             int decodedData = bits;
-            
+
             // then second base64 char; can't get padding yet, nor ws
             ch = _inputData.readUnsignedByte();
             bits = b64variant.decodeBase64Char(ch);
@@ -2802,31 +2645,7 @@ public class UTF8DataInputJsonParser
             decodedData = (decodedData << 6) | bits;
             builder.appendThreeBytes(decodedData);
         }
-    }
-
-    /*
-    /**********************************************************
-    /* Improved location updating (refactored in 2.7)
-    /**********************************************************
-     */
-
-    @Override
-    public JsonLocation getTokenLocation() {
-        return new JsonLocation(_getSourceReference(), -1L, -1L, _tokenInputRow, -1);
-    }
-
-    @Override
-    public JsonLocation getCurrentLocation() {
-        return new JsonLocation(_getSourceReference(), -1L, -1L, _currInputRow, -1);
-    }
-
-    /*
-    /**********************************************************
-    /* Internal methods, other
-    /**********************************************************
-     */
-
-    private void _closeScope(int i) throws JsonParseException {
+    }private void _closeScope(int i) throws JsonParseException {
         if (i == INT_RBRACKET) {
             if (!_parsingContext.inArray()) {
                 _reportMismatchedEndMarker(i, '}');
@@ -2841,12 +2660,20 @@ public class UTF8DataInputJsonParser
             _parsingContext = _parsingContext.clearAndGetParent();
             _currToken = JsonToken.END_OBJECT;
         }
-    }
-
-    /**
-     * Helper method needed to fix [Issue#148], masking of 0x00 character
-     */
-    private final static int pad(int q, int bytes) {
-        return (bytes == 4) ? q : (q | (-1 << (bytes << 3)));
-    }
-}
+    }@Override
+    protected void _closeInput() throws IOException { }private final void _checkMatchEnd(String matchStr, int i, int ch) throws IOException {
+        // but actually only alphanums are problematic
+        char c = (char) _decodeCharForError(ch);
+        if (Character.isJavaIdentifierPart(c)) {
+            _reportInvalidToken(c, matchStr.substring(0, i));
+        }
+    }public UTF8DataInputJsonParser(IOContext ctxt, int features, DataInput inputData,
+            ObjectCodec codec, ByteQuadsCanonicalizer sym,
+            int firstByte)
+    {
+        super(ctxt, features);
+        _objectCodec = codec;
+        _symbols = sym;
+        _inputData = inputData;
+        _nextByte = firstByte;
+    }}
diff --git a/src/test/java/com/fasterxml/jackson/core/TestVersions.java b/src/test/java/com/fasterxml/jackson/core/TestVersions.java
index 865be6f1..5d270d91 100644
--- a/src/test/java/com/fasterxml/jackson/core/TestVersions.java
+++ b/src/test/java/com/fasterxml/jackson/core/TestVersions.java
@@ -1,5 +1,6 @@
 package com.fasterxml.jackson.core;
 
+import com.fasterxml.jackson.core.io.ReaderBasedJsonParser;
 import com.fasterxml.jackson.core.json.*;
 import com.fasterxml.jackson.core.io.IOContext;
 import com.fasterxml.jackson.core.sym.CharsToNameCanonicalizer;
diff --git a/src/test/java/com/fasterxml/jackson/core/read/TrailingCommasTest.java b/src/test/java/com/fasterxml/jackson/core/read/TrailingCommasTest.java
index 5ca9eb38..6719059f 100644
--- a/src/test/java/com/fasterxml/jackson/core/read/TrailingCommasTest.java
+++ b/src/test/java/com/fasterxml/jackson/core/read/TrailingCommasTest.java
@@ -5,7 +5,7 @@ import com.fasterxml.jackson.core.JsonFactory;
 import com.fasterxml.jackson.core.JsonParser;
 import com.fasterxml.jackson.core.JsonParser.Feature;
 import com.fasterxml.jackson.core.JsonToken;
-import com.fasterxml.jackson.core.json.UTF8DataInputJsonParser;
+import com.fasterxml.jackson.core.io.UTF8DataInputJsonParser;
 
 import org.junit.Test;
 import org.junit.runner.RunWith;
diff --git a/src/test/java/com/fasterxml/jackson/core/sym/SymbolTableMergingTest.java b/src/test/java/com/fasterxml/jackson/core/sym/SymbolTableMergingTest.java
index 766fada9..3cb1074e 100644
--- a/src/test/java/com/fasterxml/jackson/core/sym/SymbolTableMergingTest.java
+++ b/src/test/java/com/fasterxml/jackson/core/sym/SymbolTableMergingTest.java
@@ -3,7 +3,7 @@ package com.fasterxml.jackson.core.sym;
 import java.io.IOException;
 
 import com.fasterxml.jackson.core.*;
-import com.fasterxml.jackson.core.json.ReaderBasedJsonParser;
+import com.fasterxml.jackson.core.io.ReaderBasedJsonParser;
 import com.fasterxml.jackson.core.json.UTF8StreamJsonParser;
 
 /**

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

file="/home/jackson-core/pom.xml"
old_version="2.15.0-rc2-SNAPSHOT"
new_version="2.15.5-SNAPSHOT"
sed -i "s/$old_version/$new_version/g" "$file"

mvn clean test -Dmaven.test.skip=false -DfailIfNoTests=false || true
