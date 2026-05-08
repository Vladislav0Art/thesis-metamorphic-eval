#!/bin/bash
set -e

cd /home/jackson-core
git reset --hard
bash /home/check_git_changes.sh
git checkout f42556388bb8ad547a55e4ee7cfb52a99f670186

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/com/fasterxml/jackson/core/JsonFactory.java b/src/main/java/com/fasterxml/jackson/core/JsonFactory.java
index 2e33185a..8f28e3d3 100644
--- a/src/main/java/com/fasterxml/jackson/core/JsonFactory.java
+++ b/src/main/java/com/fasterxml/jackson/core/JsonFactory.java
@@ -12,6 +12,8 @@ import com.fasterxml.jackson.core.format.InputAccessor;
 import com.fasterxml.jackson.core.format.MatchStrength;
 import com.fasterxml.jackson.core.io.*;
 import com.fasterxml.jackson.core.json.*;
+import com.fasterxml.jackson.core.json.parsers.JsonParserFromReader;
+import com.fasterxml.jackson.core.json.parsers.UTF8JsonInputParser;
 import com.fasterxml.jackson.core.sym.ByteQuadsCanonicalizer;
 import com.fasterxml.jackson.core.sym.CharsToNameCanonicalizer;
 import com.fasterxml.jackson.core.util.BufferRecycler;
@@ -1287,7 +1289,7 @@ public class JsonFactory
      * @since 2.1
      */
     protected JsonParser _createParser(Reader r, IOContext ctxt) throws IOException {
-        return new ReaderBasedJsonParser(ctxt, _parserFeatures, r, _objectCodec,
+        return new JsonParserFromReader(ctxt, _parserFeatures, r, _objectCodec,
                 _rootCharSymbols.makeChild(_factoryFeatures));
     }
 
@@ -1299,7 +1301,7 @@ public class JsonFactory
      */
     protected JsonParser _createParser(char[] data, int offset, int len, IOContext ctxt,
             boolean recyclable) throws IOException {
-        return new ReaderBasedJsonParser(ctxt, _parserFeatures, null, _objectCodec,
+        return new JsonParserFromReader(ctxt, _parserFeatures, null, _objectCodec,
                 _rootCharSymbols.makeChild(_factoryFeatures),
                         data, offset, offset+len, recyclable);
     }
@@ -1337,7 +1339,7 @@ public class JsonFactory
         // at least handle possible UTF-8 BOM
         int firstByte = ByteSourceJsonBootstrapper.skipUTF8BOM(input);
         ByteQuadsCanonicalizer can = _byteSymbolCanonicalizer.makeChild(_factoryFeatures);
-        return new UTF8DataInputJsonParser(ctxt, _parserFeatures, input,
+        return new UTF8JsonInputParser(ctxt, _parserFeatures, input,
                 _objectCodec, can, firstByte);
     }
 
diff --git a/src/main/java/com/fasterxml/jackson/core/json/ByteSourceJsonBootstrapper.java b/src/main/java/com/fasterxml/jackson/core/json/ByteSourceJsonBootstrapper.java
index 6ff84e9c..880bfb6b 100644
--- a/src/main/java/com/fasterxml/jackson/core/json/ByteSourceJsonBootstrapper.java
+++ b/src/main/java/com/fasterxml/jackson/core/json/ByteSourceJsonBootstrapper.java
@@ -6,6 +6,7 @@ import com.fasterxml.jackson.core.*;
 import com.fasterxml.jackson.core.format.InputAccessor;
 import com.fasterxml.jackson.core.format.MatchStrength;
 import com.fasterxml.jackson.core.io.*;
+import com.fasterxml.jackson.core.json.parsers.JsonParserFromReader;
 import com.fasterxml.jackson.core.sym.ByteQuadsCanonicalizer;
 import com.fasterxml.jackson.core.sym.CharsToNameCanonicalizer;
 
@@ -255,7 +256,7 @@ public final class ByteSourceJsonBootstrapper
                         _inputBuffer, _inputPtr, _inputEnd, _bufferRecyclable);
             }
         }
-        return new ReaderBasedJsonParser(_context, parserFeatures, constructReader(), codec,
+        return new JsonParserFromReader(_context, parserFeatures, constructReader(), codec,
                 rootCharSymbols.makeChild(factoryFeatures));
     }
 
diff --git a/src/main/java/com/fasterxml/jackson/core/json/ReaderBasedJsonParser.java b/src/main/java/com/fasterxml/jackson/core/json/ReaderBasedJsonParser.java
deleted file mode 100644
index a0014052..00000000
--- a/src/main/java/com/fasterxml/jackson/core/json/ReaderBasedJsonParser.java
+++ /dev/null
@@ -1,2854 +0,0 @@
-package com.fasterxml.jackson.core.json;
-
-import java.io.*;
-
-import com.fasterxml.jackson.core.*;
-import com.fasterxml.jackson.core.base.ParserBase;
-import com.fasterxml.jackson.core.io.CharTypes;
-import com.fasterxml.jackson.core.io.IOContext;
-import com.fasterxml.jackson.core.sym.CharsToNameCanonicalizer;
-import com.fasterxml.jackson.core.util.*;
-
-import static com.fasterxml.jackson.core.JsonTokenId.*;
-
-/**
- * This is a concrete implementation of {@link JsonParser}, which is
- * based on a {@link java.io.Reader} to handle low-level character
- * conversion tasks.
- */
-public class ReaderBasedJsonParser // final in 2.3, earlier
-    extends ParserBase
-{
-    protected final static int FEAT_MASK_TRAILING_COMMA = Feature.ALLOW_TRAILING_COMMA.getMask();
-
-    // Latin1 encoding is not supported, but we do use 8-bit subset for
-    // pre-processing task, to simplify first pass, keep it fast.
-    protected final static int[] _icLatin1 = CharTypes.getInputCodeLatin1();
-
-    /*
-    /**********************************************************
-    /* Input configuration
-    /**********************************************************
-     */
-
-    /**
-     * Reader that can be used for reading more content, if one
-     * buffer from input source, but in some cases pre-loaded buffer
-     * is handed to the parser.
-     */
-    protected Reader _reader;
-
-    /**
-     * Current buffer from which data is read; generally data is read into
-     * buffer from input source.
-     */
-    protected char[] _inputBuffer;
-
-    /**
-     * Flag that indicates whether the input buffer is recycable (and
-     * needs to be returned to recycler once we are done) or not.
-     *<p>
-     * If it is not, it also means that parser can NOT modify underlying
-     * buffer.
-     */
-    protected boolean _bufferRecyclable;
-
-    /*
-    /**********************************************************
-    /* Configuration
-    /**********************************************************
-     */
-
-    protected ObjectCodec _objectCodec;
-
-    final protected CharsToNameCanonicalizer _symbols;
-
-    final protected int _hashSeed;
-
-    /*
-    /**********************************************************
-    /* Parsing state
-    /**********************************************************
-     */
-
-    /**
-     * Flag that indicates that the current token has not yet
-     * been fully processed, and needs to be finished for
-     * some access (or skipped to obtain the next token)
-     */
-    protected boolean _tokenIncomplete;
-
-    /**
-     * Value of {@link #_inputPtr} at the time when the first character of
-     * name token was read. Used for calculating token location when requested;
-     * combined with {@link #_currInputProcessed}, may be updated appropriately
-     * as needed.
-     *
-     * @since 2.7
-     */
-    protected long _nameStartOffset;
-
-    /**
-     * @since 2.7
-     */
-    protected int _nameStartRow;
-
-    /**
-     * @since 2.7
-     */
-    protected int _nameStartCol;
-
-    /*
-    /**********************************************************
-    /* Life-cycle
-    /**********************************************************
-     */
-
-    /**
-     * Method called when caller wants to provide input buffer directly,
-     * and it may or may not be recyclable use standard recycle context.
-     *
-     * @since 2.4
-     */
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
-
-    /**
-     * Method called when input comes as a {@link java.io.Reader}, and buffer allocation
-     * can be done using default mechanism.
-     */
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
-
-    /*
-    /**********************************************************
-    /* Base method defs, overrides
-    /**********************************************************
-     */
-
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
-
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
-
-    /**
-     * Method called to release internal buffers owned by the base
-     * reader. This may be called along with {@link #_closeInput} (for
-     * example, when explicitly closing this reader instance), or
-     * separately (if need be).
-     */
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
-
-    /*
-    /**********************************************************
-    /* Low-level access, supporting
-    /**********************************************************
-     */
-
-    protected void _loadMoreGuaranteed() throws IOException {
-        if (!_loadMore()) { _reportInvalidEOF(); }
-    }
-    
-    protected boolean _loadMore() throws IOException
-    {
-        final int bufSize = _inputEnd;
-
-        _currInputProcessed += bufSize;
-        _currInputRowStart -= bufSize;
-
-        // 26-Nov-2015, tatu: Since name-offset requires it too, must offset
-        //   this increase to avoid "moving" name-offset, resulting most likely
-        //   in negative value, which is fine as combine value remains unchanged.
-        _nameStartOffset -= bufSize;
-
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
-
-    /*
-    /**********************************************************
-    /* Public API, data access
-    /**********************************************************
-     */
-
-    /**
-     * Method for accessing textual representation of the current event;
-     * if no current event (before first call to {@link #nextToken}, or
-     * after encountering end-of-input), returns null.
-     * Method can be called for any event.
-     */
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
-
-    @Override // since 2.8
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
-    
-    // // // Let's override default impls for improved performance
-
-    // @since 2.1
-    @Override
-    public final String getValueAsString() throws IOException
-    {
-        if (_currToken == JsonToken.VALUE_STRING) {
-            if (_tokenIncomplete) {
-                _tokenIncomplete = false;
-                _finishString(); // only strings can be incomplete
-            }
-            return _textBuffer.contentsAsString();
-        }
-        if (_currToken == JsonToken.FIELD_NAME) {
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
-        }
-        if (_currToken == JsonToken.FIELD_NAME) {
-            return getCurrentName();
-        }
-        return super.getValueAsString(defValue);
-    }
-
-    protected final String _getText2(JsonToken t) {
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
-            return t.asString();
-        }
-    }
-
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
-                }
-                // fall through
-            case ID_NUMBER_INT:
-            case ID_NUMBER_FLOAT:
-                return _textBuffer.getTextBuffer();
-            default:
-                return _currToken.asCharArray();
-            }
-        }
-        return null;
-    }
-
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
-            }
-        }
-        return 0;
-    }
-
-    @Override
-    public final int getTextOffset() throws IOException
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
-        }
-        return 0;
-    }
-
-    @Override
-    public byte[] getBinaryValue(Base64Variant b64variant) throws IOException
-    {
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
-        }
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
-        }
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
-    @Override
-    public final JsonToken nextToken() throws IOException
-    {
-        /* First: field names are special -- we will always tokenize
-         * (part of) value along with field name to simplify
-         * state handling. If so, can and need to use secondary token:
-         */
-        if (_currToken == JsonToken.FIELD_NAME) {
-            return _nextAfterName();
-        }
-        // But if we didn't already have a name, and (partially?) decode number,
-        // need to ensure no numeric information is leaked
-        _numTypesValid = NR_UNKNOWN;
-        if (_tokenIncomplete) {
-            _skipString(); // only strings can be partial
-        }
-        int i = _skipWSOrEnd();
-        if (i < 0) { // end-of-input
-            // Should actually close/release things
-            // like input source, symbol table and recyclable buffers now.
-            close();
-            return (_currToken = null);
-        }
-        // clear any data retained so far
-        _binaryValue = null;
-
-        // Closing scope?
-        if (i == INT_RBRACKET || i == INT_RCURLY) {
-            _closeScope(i);
-            return _currToken;
-        }
-
-        // Nope: do we then expect a comma?
-        if (_parsingContext.expectComma()) {
-            i = _skipComma(i);
-
-            // Was that a trailing comma?
-            if ((_features & FEAT_MASK_TRAILING_COMMA) != 0) {
-                if ((i == INT_RBRACKET) || (i == INT_RCURLY)) {
-                    _closeScope(i);
-                    return _currToken;
-                }
-            }
-        }
-
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
-        }
-        _updateLocation();
-
-        // Ok: we must have a value... what is it?
-
-        JsonToken t;
-
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
-            }
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
-
-        _numTypesValid = NR_UNKNOWN;
-        if (_currToken == JsonToken.FIELD_NAME) {
-            _nextAfterName();
-            return null;
-        }
-        if (_tokenIncomplete) {
-            _skipString();
-        }
-        int i = _skipWSOrEnd();
-        if (i < 0) {
-            close();
-            _currToken = null;
-            return null;
-        }
-        _binaryValue = null;
-        if (i == INT_RBRACKET) {
-            _updateLocation();
-            if (!_parsingContext.inArray()) {
-                _reportMismatchedEndMarker(i, '}');
-            }
-            _parsingContext = _parsingContext.clearAndGetParent();
-            _currToken = JsonToken.END_ARRAY;
-            return null;
-        }
-        if (i == INT_RCURLY) {
-            _updateLocation();
-            if (!_parsingContext.inObject()) {
-                _reportMismatchedEndMarker(i, ']');
-            }
-            _parsingContext = _parsingContext.clearAndGetParent();
-            _currToken = JsonToken.END_OBJECT;
-            return null;
-        }
-        if (_parsingContext.expectComma()) {
-            i = _skipComma(i);
-        }
-        if (!_parsingContext.inObject()) {
-            _updateLocation();
-            _nextTokenNotInObject(i);
-            return null;
-        }
-
-        _updateNameLocation();
-        String name = (i == INT_QUOTE) ? _parseName() : _handleOddName(i);
-        _parsingContext.setCurrentName(name);
-        _currToken = JsonToken.FIELD_NAME;
-        i = _skipColon();
-
-        _updateLocation();
-        if (i == INT_QUOTE) {
-            _tokenIncomplete = true;
-            _nextToken = JsonToken.VALUE_STRING;
-            return name;
-        }
-        
-        // Ok: we must have a value... what is it?
-
-        JsonToken t;
-
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
-        }
-        _nextToken = t;
-        return name;
-    }
-
-    private final void _isNextTokenNameYes(int i) throws IOException
-    {
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
-        }
-        _nextToken = _handleOddValue(i);
-    }
-
-    protected boolean _isNextTokenNameMaybe(int i, String nameToMatch) throws IOException
-    {
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
-        }
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
-        }
-        _nextToken = t;
-        return nameToMatch.equals(name);
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
-        }
-        return (_currToken = _handleOddValue(i));
-    }
-
-    // note: identical to one in UTF8StreamJsonParser
-    @Override
-    public final String nextTextValue() throws IOException
-    {
-        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
-            _nameCopied = false;
-            JsonToken t = _nextToken;
-            _nextToken = null;
-            _currToken = t;
-            if (t == JsonToken.VALUE_STRING) {
-                if (_tokenIncomplete) {
-                    _tokenIncomplete = false;
-                    _finishString();
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
-        // !!! TODO: optimize this case as well
-        return (nextToken() == JsonToken.VALUE_STRING) ? getText() : null;
-    }
-
-    // note: identical to one in Utf8StreamParser
-    @Override
-    public final int nextIntValue(int defaultValue) throws IOException
-    {
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
-            }
-            return defaultValue;
-        }
-        // !!! TODO: optimize this case as well
-        return (nextToken() == JsonToken.VALUE_NUMBER_INT) ? getIntValue() : defaultValue;
-    }
-
-    // note: identical to one in Utf8StreamParser
-    @Override
-    public final long nextLongValue(long defaultValue) throws IOException
-    {
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
-        // !!! TODO: optimize this case as well
-        return (nextToken() == JsonToken.VALUE_NUMBER_INT) ? getLongValue() : defaultValue;
-    }
-
-    // note: identical to one in UTF8StreamJsonParser
-    @Override
-    public final Boolean nextBooleanValue() throws IOException
-    {
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
-            }
-            if (t == JsonToken.START_ARRAY) {
-                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
-            } else if (t == JsonToken.START_OBJECT) {
-                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
-            }
-            return null;
-        }
-        JsonToken t = nextToken();
-        if (t != null) {
-            int id = t.id();
-            if (id == ID_TRUE) return Boolean.TRUE;
-            if (id == ID_FALSE) return Boolean.FALSE;
-        }
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
-    {
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
-        }
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
-            }
-            ch = (int) _inputBuffer[ptr++];
-            if (ch < INT_0 || ch > INT_9) {
-                break int_loop;
-            }
-            ++intLen;
-        }
-        if (ch == INT_PERIOD || ch == INT_e || ch == INT_E) {
-            _inputPtr = ptr;
-            return _parseFloat(ch, startPtr, ptr, false, intLen);
-        }
-        // Got it all: let's add to text buffer for parsing, access
-        --ptr; // need to push back following separator
-        _inputPtr = ptr;
-        // As per #105, need separating space between root values; check here
-        if (_parsingContext.inRoot()) {
-            _verifyRootSpace(ch);
-        }
-        int len = ptr-startPtr;
-        _textBuffer.resetWithShared(_inputBuffer, startPtr, len);
-        return resetInt(false, intLen);
-    }
-
-    private final JsonToken _parseFloat(int ch, int startPtr, int ptr, boolean neg, int intLen)
-        throws IOException
-    {
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
-            }
-        }
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
-                }
-                ch = (int) _inputBuffer[ptr++];
-            }
-            while (ch <= INT_9 && ch >= INT_0) {
-                ++expLen;
-                if (ptr >= inputLen) {
-                    _inputPtr = startPtr;
-                    return _parseNumber2(neg, startPtr);
-                }
-                ch = (int) _inputBuffer[ptr++];
-            }
-            // must be followed by sequence of ints, one minimum
-            if (expLen == 0) {
-                reportUnexpectedNumberChar(ch, "Exponent indicator not followed by a digit");
-            }
-        }
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
-    {
-        int ptr = _inputPtr;
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
-        }
-        int intLen = 1; // already got one
-
-        // First let's get the obligatory integer part:
-        int_loop:
-        while (true) {
-            if (ptr >= inputLen) {
-                return _parseNumber2(true, startPtr);
-            }
-            ch = (int) _inputBuffer[ptr++];
-            if (ch < INT_0 || ch > INT_9) {
-                break int_loop;
-            }
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
-                }
-                c = _inputBuffer[_inputPtr++];
-                if (c < INT_0 || c > INT_9) {
-                    break fract_loop;
-                }
-                ++fractLen;
-                if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
-                    outPtr = 0;
-                }
-                outBuf[outPtr++] = c;
-            }
-            // must be followed by sequence of ints, one minimum
-            if (fractLen == 0) {
-                reportUnexpectedNumberChar(c, "Decimal point not followed by a digit");
-            }
-        }
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
-            }
-        }
-
-        // Ok; unless we hit end-of-input, need to push last char read back
-        if (!eof) {
-            --_inputPtr;
-            if (_parsingContext.inRoot()) {
-                _verifyRootSpace(c);
-            }
-        }
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
-            }
-        }
-        // and offline the less common case
-        return _verifyNLZ2();
-    }
-
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
-                }
-                ++_inputPtr; // skip previous zero
-                if (ch != '0') { // followed by other number; return
-                    break;
-                }
-            }
-        }
-        return ch;
-    }
-
-    /**
-     * Method called if expected numeric value (due to leading sign) does not
-     * look like a number
-     */
-    protected JsonToken _handleInvalidNumberStart(int ch, boolean negative) throws IOException
-    {
-        if (ch == 'I') {
-            if (_inputPtr >= _inputEnd) {
-                if (!_loadMore()) {
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
-                }
-            }
-            char c = _inputBuffer[_inputPtr++];
-            int i = (int) c;
-            if (i <= INT_BACKSLASH) {
-                if (i == INT_BACKSLASH) {
-                    /* Although chars outside of BMP are to be escaped as
-                     * an UTF-16 surrogate pair, does that affect decoding?
-                     * For now let's assume it does not.
-                     */
-                    c = _decodeEscaped();
-                } else if (i <= endChar) {
-                    if (i == endChar) {
-                        break;
-                    }
-                    if (i < INT_SPACE) {
-                        _throwUnquotedSpace(i, "name");
-                    }
-                }
-            }
-            hash = (hash * CharsToNameCanonicalizer.HASH_MULT) + c;
-            // Ok, let's add char to output:
-            outBuf[outPtr++] = c;
-
-            // Need more room?
-            if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
-                outPtr = 0;
-            }
-        }
-        _textBuffer.setCurrentLength(outPtr);
-        {
-            TextBuffer tb = _textBuffer;
-            char[] buf = tb.getTextBuffer();
-            int start = tb.getTextOffset();
-            int len = tb.size();
-            return _symbols.findSymbol(buf, start, len, hash);
-        }
-    }
-
-    /**
-     * Method called when we see non-white space character other
-     * than double quote, when expecting a field name.
-     * In standard mode will just throw an expection; but
-     * in non-standard modes may be able to parse name.
-     */
-    protected String _handleOddName(int i) throws IOException
-    {
-        // [JACKSON-173]: allow single quotes
-        if (i == '\'' && isEnabled(Feature.ALLOW_SINGLE_QUOTES)) {
-            return _parseAposName();
-        }
-        // [JACKSON-69]: allow unquoted names if feature enabled:
-        if (!isEnabled(Feature.ALLOW_UNQUOTED_FIELD_NAMES)) {
-            _reportUnexpectedChar(i, "was expecting double-quote to start field name");
-        }
-        final int[] codes = CharTypes.getInputCodeLatin1JsNames();
-        final int maxCode = codes.length;
-
-        // Also: first char must be a valid name char, but NOT be number
-        boolean firstOk;
-
-        if (i < maxCode) { // identifier, or a number ([Issue#102])
-            firstOk = (codes[i] == 0);
-        } else {
-            firstOk = Character.isJavaIdentifierPart((char) i);
-        }
-        if (!firstOk) {
-            _reportUnexpectedChar(i, "was expecting either valid name character (for unquoted name) or double-quote (for quoted) to start field name");
-        }
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
-                }
-                hash = (hash * CharsToNameCanonicalizer.HASH_MULT) + ch;
-                ++ptr;
-            } while (ptr < inputLen);
-        }
-        int start = _inputPtr-1;
-        _inputPtr = ptr;
-        return _handleOddName2(start, hash, codes);
-    }
-
-    protected String _parseAposName() throws IOException
-    {
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
-                }
-                hash = (hash * CharsToNameCanonicalizer.HASH_MULT) + ch;
-                ++ptr;
-            } while (ptr < inputLen);
-        }
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
-    {
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
-            }
-            break;
-        case ']':
-            /* 28-Mar-2016: [core#116]: If Feature.ALLOW_MISSING_VALUES is enabled
-             *   we may allow "missing values", that is, encountering a trailing
-             *   comma or closing marker where value would be expected
-             */
-            if (!_parsingContext.inArray()) {
-                break;
-            }
-            // fall through
-        case ',':
-            if (isEnabled(Feature.ALLOW_MISSING_VALUES)) {
-                --_inputPtr;
-                return JsonToken.VALUE_NULL;
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
-            if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
-                return resetAsNaN("Infinity", Double.POSITIVE_INFINITY);
-            }
-            _reportError("Non-standard token 'Infinity': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
-            break;
-        case '+': // note: '-' is taken as number
-            if (_inputPtr >= _inputEnd) {
-                if (!_loadMore()) {
-                    _reportInvalidEOFInValue(JsonToken.VALUE_NUMBER_INT);
-                }
-            }
-            return _handleInvalidNumberStart(_inputBuffer[_inputPtr++], false);
-        }
-        // [core#77] Try to decode most likely token
-        if (Character.isJavaIdentifierStart(i)) {
-            _reportInvalidToken(""+((char) i), "('true', 'false' or 'null')");
-        }
-        // but if it doesn't look like a token:
-        _reportUnexpectedChar(i, "expected a valid value (number, String, array, object, 'true', 'false' or 'null')");
-        return null;
-    }
-
-    protected JsonToken _handleApos() throws IOException
-    {
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
-                        break;
-                    }
-                    if (i < INT_SPACE) {
-                        _throwUnquotedSpace(i, "string value");
-                    }
-                }
-            }
-            // Need more room?
-            if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
-                outPtr = 0;
-            }
-            // Ok, let's add char to output:
-            outBuf[outPtr++] = c;
-        }
-        _textBuffer.setCurrentLength(outPtr);
-        return JsonToken.VALUE_STRING;
-    }
-
-    private String _handleOddName2(int startPtr, int hash, int[] codes) throws IOException
-    {
-        _textBuffer.resetWithShared(_inputBuffer, startPtr, (_inputPtr - startPtr));
-        char[] outBuf = _textBuffer.getCurrentSegment();
-        int outPtr = _textBuffer.getCurrentSegmentSize();
-        final int maxCode = codes.length;
-
-        while (true) {
-            if (_inputPtr >= _inputEnd) {
-                if (!_loadMore()) { // acceptable for now (will error out later)
-                    break;
-                }
-            }
-            char c = _inputBuffer[_inputPtr];
-            int i = (int) c;
-            if (i <= maxCode) {
-                if (codes[i] != 0) {
-                    break;
-                }
-            } else if (!Character.isJavaIdentifierPart(c)) {
-                break;
-            }
-            ++_inputPtr;
-            hash = (hash * CharsToNameCanonicalizer.HASH_MULT) + i;
-            // Ok, let's add char to output:
-            outBuf[outPtr++] = c;
-
-            // Need more room?
-            if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
-                outPtr = 0;
-            }
-        }
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
-    @Override
-    protected final void _finishString() throws IOException
-    {
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
-
-            do {
-                int ch = _inputBuffer[ptr];
-                if (ch < maxCode && codes[ch] != 0) {
-                    if (ch == '"') {
-                        _textBuffer.resetWithShared(_inputBuffer, _inputPtr, (ptr-_inputPtr));
-                        _inputPtr = ptr+1;
-                        // Yes, we got it all
-                        return;
-                    }
-                    break;
-                }
-                ++ptr;
-            } while (ptr < inputLen);
-        }
-
-        /* Either ran out of input, or bumped into an escape
-         * sequence...
-         */
-        _textBuffer.resetWithCopy(_inputBuffer, _inputPtr, (ptr-_inputPtr));
-        _inputPtr = ptr;
-        _finishString2();
-    }
-
-    protected void _finishString2() throws IOException
-    {
-        char[] outBuf = _textBuffer.getCurrentSegment();
-        int outPtr = _textBuffer.getCurrentSegmentSize();
-        final int[] codes = _icLatin1;
-        final int maxCode = codes.length;
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
-            }
-            // Need more room?
-            if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
-                outPtr = 0;
-            }
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
-
-        while (true) {
-            if (inPtr >= inLen) {
-                _inputPtr = inPtr;
-                if (!_loadMore()) {
-                    _reportInvalidEOF(": was expecting closing quote for a string value",
-                            JsonToken.VALUE_STRING);
-                }
-                inPtr = _inputPtr;
-                inLen = _inputEnd;
-            }
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
-                        break;
-                    }
-                    if (i < INT_SPACE) {
-                        _inputPtr = inPtr;
-                        _throwUnquotedSpace(i, "string value");
-                    }
-                }
-            }
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
-            }
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
-                    }
-                    ++_inputPtr;
-                    return i;
-                }
-            }
-            return _skipColon2(true); // true -> skipped colon
-        }
-        if (c == ' ' || c == '\t') {
-            c = _inputBuffer[++_inputPtr];
-        }
-        if (c == ':') {
-            int i = _inputBuffer[++_inputPtr];
-            if (i > INT_SPACE) {
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
-                    }
-                    ++_inputPtr;
-                    return i;
-                }
-            }
-            return _skipColon2(true);
-        }
-        return _skipColon2(false);
-    }
-
-    private final int _skipColon2(boolean gotColon) throws IOException
-    {
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
-            }
-            if (i < INT_SPACE) {
-                if (i == INT_LF) {
-                    ++_currInputRow;
-                    _currInputRowStart = _inputPtr;
-                } else if (i == INT_CR) {
-                    _skipCR();
-                } else if (i != INT_TAB) {
-                    _throwInvalidSpace(i);
-                }
-            }
-        }
-        _reportInvalidEOF(" within/between "+_parsingContext.typeDesc()+" entries",
-                null);
-        return -1;
-    }
-
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
-                }
-            } else if (i == INT_SPACE || i == INT_TAB) {
-                i = (int) _inputBuffer[ptr++];
-                if (i > INT_SPACE) {
-                    if (i != INT_SLASH && i != INT_HASH) {
-                        _inputPtr = ptr;
-                        return i;
-                    }
-                }
-            }
-            _inputPtr = ptr-1;
-            return _skipColon2(true); // true -> skipped colon
-        }
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
-                }
-            } else if (i == INT_SPACE || i == INT_TAB) {
-                i = (int) _inputBuffer[ptr++];
-                if (i > INT_SPACE) {
-                    if (i != INT_SLASH && i != INT_HASH) {
-                        _inputPtr = ptr;
-                        return i;
-                    }
-                }
-            }
-        }
-        _inputPtr = ptr-1;
-        return _skipColon2(gotColon);
-    }
-
-    // Primary loop: no reloading, comment handling
-    private final int _skipComma(int i) throws IOException
-    {
-        if (i != INT_COMMA) {
-            _reportUnexpectedChar(i, "was expecting comma to separate "+_parsingContext.typeDesc()+" entries");
-        }
-        while (_inputPtr < _inputEnd) {
-            i = (int) _inputBuffer[_inputPtr++];
-            if (i > INT_SPACE) {
-                if (i == INT_SLASH || i == INT_HASH) {
-                    --_inputPtr;
-                    return _skipAfterComma2();
-                }
-                return i;
-            }
-            if (i < INT_SPACE) {
-                if (i == INT_LF) {
-                    ++_currInputRow;
-                    _currInputRowStart = _inputPtr;
-                } else if (i == INT_CR) {
-                    _skipCR();
-                } else if (i != INT_TAB) {
-                    _throwInvalidSpace(i);
-                }
-            }
-        }
-        return _skipAfterComma2();
-    }
-
-    private final int _skipAfterComma2() throws IOException
-    {
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
-                return i;
-            }
-            if (i < INT_SPACE) {
-                if (i == INT_LF) {
-                    ++_currInputRow;
-                    _currInputRowStart = _inputPtr;
-                } else if (i == INT_CR) {
-                    _skipCR();
-                } else if (i != INT_TAB) {
-                    _throwInvalidSpace(i);
-                }
-            }
-        }
-        throw _constructError("Unexpected end-of-input within/between "+_parsingContext.typeDesc()+" entries");
-    }
-
-    private final int _skipWSOrEnd() throws IOException
-    {
-        // Let's handle first character separately since it is likely that
-        // it is either non-whitespace; or we have longer run of white space
-        if (_inputPtr >= _inputEnd) {
-            if (!_loadMore()) {
-                return _eofAsNextChar();
-            }
-        }
-        int i = _inputBuffer[_inputPtr++];
-        if (i > INT_SPACE) {
-            if (i == INT_SLASH || i == INT_HASH) {
-                --_inputPtr;
-                return _skipWSOrEnd2();
-            }
-            return i;
-        }
-        if (i != INT_SPACE) {
-            if (i == INT_LF) {
-                ++_currInputRow;
-                _currInputRowStart = _inputPtr;
-            } else if (i == INT_CR) {
-                _skipCR();
-            } else if (i != INT_TAB) {
-                _throwInvalidSpace(i);
-            }
-        }
-
-        while (_inputPtr < _inputEnd) {
-            i = (int) _inputBuffer[_inputPtr++];
-            if (i > INT_SPACE) {
-                if (i == INT_SLASH || i == INT_HASH) {
-                    --_inputPtr;
-                    return _skipWSOrEnd2();
-                }
-                return i;
-            }
-            if (i != INT_SPACE) {
-                if (i == INT_LF) {
-                    ++_currInputRow;
-                    _currInputRowStart = _inputPtr;
-                } else if (i == INT_CR) {
-                    _skipCR();
-                } else if (i != INT_TAB) {
-                    _throwInvalidSpace(i);
-                }
-            }
-        }
-        return _skipWSOrEnd2();
-    }
-
-    private int _skipWSOrEnd2() throws IOException
-    {
-        while (true) {
-            if (_inputPtr >= _inputEnd) {
-                if (!_loadMore()) { // We ran out of input...
-                    return _eofAsNextChar();
-                }
-            }
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
-                }
-            }
-        }
-    }
-
-    private void _skipComment() throws IOException
-    {
-        if (!isEnabled(Feature.ALLOW_COMMENTS)) {
-            _reportUnexpectedChar('/', "maybe a (non-standard) comment? (not recognized as one since Feature 'ALLOW_COMMENTS' not enabled for parser)");
-        }
-        // First: check which comment (if either) it is:
-        if (_inputPtr >= _inputEnd && !_loadMore()) {
-            _reportInvalidEOF(" in a comment", null);
-        }
-        char c = _inputBuffer[_inputPtr++];
-        if (c == '/') {
-            _skipLine();
-        } else if (c == '*') {
-            _skipCComment();
-        } else {
-            _reportUnexpectedChar(c, "was expecting either '*' or '/' for a comment");
-        }
-    }
-
-    private void _skipCComment() throws IOException
-    {
-        // Ok: need the matching '*/'
-        while ((_inputPtr < _inputEnd) || _loadMore()) {
-            int i = (int) _inputBuffer[_inputPtr++];
-            if (i <= '*') {
-                if (i == '*') { // end?
-                    if ((_inputPtr >= _inputEnd) && !_loadMore()) {
-                        break;
-                    }
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
-                    }
-                }
-            }
-        }
-        _reportInvalidEOF(" in a comment", null);
-    }
-
-    private boolean _skipYAMLComment() throws IOException
-    {
-        if (!isEnabled(Feature.ALLOW_YAML_COMMENTS)) {
-            return false;
-        }
-        _skipLine();
-        return true;
-    }
-
-    private void _skipLine() throws IOException
-    {
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
-                    break;
-                } else if (i != INT_TAB) {
-                    _throwInvalidSpace(i);
-                }
-            }
-        }
-    }
-
-    @Override
-    protected char _decodeEscaped() throws IOException
-    {
-        if (_inputPtr >= _inputEnd) {
-            if (!_loadMore()) {
-                _reportInvalidEOF(" in character escape sequence", JsonToken.VALUE_STRING);
-            }
-        }
-        char c = _inputBuffer[_inputPtr++];
-
-        switch ((int) c) {
-            // First, ones that are mapped
-        case 'b':
-            return '\b';
-        case 't':
-            return '\t';
-        case 'n':
-            return '\n';
-        case 'f':
-            return '\f';
-        case 'r':
-            return '\r';
-
-            // And these are to be returned as they are
-        case '"':
-        case '/':
-        case '\\':
-            return c;
-
-        case 'u': // and finally hex-escaped
-            break;
-
-        default:
-            return _handleUnrecognizedCharacterEscape(c);
-        }
-
-        // Ok, a hex escape. Need 4 characters
-        int value = 0;
-        for (int i = 0; i < 4; ++i) {
-            if (_inputPtr >= _inputEnd) {
-                if (!_loadMore()) {
-                    _reportInvalidEOF(" in character escape sequence", JsonToken.VALUE_STRING);
-                }
-            }
-            int ch = (int) _inputBuffer[_inputPtr++];
-            int digit = CharTypes.charToHex(ch);
-            if (digit < 0) {
-                _reportUnexpectedChar(ch, "expected a hex-digit for character escape sequence");
-            }
-            value = (value << 4) | digit;
-        }
-        return (char) value;
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
-     * Efficient handling for incremental parsing of base64-encoded
-     * textual content.
-     */
-    @SuppressWarnings("resource")
-    protected byte[] _decodeBase64(Base64Variant b64variant) throws IOException
-    {
-        ByteArrayBuilder builder = _getByteArrayBuilder();
-
-        //main_loop:
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
-            if (bits < 0) {
-                if (ch == '"') { // reached the end, fair and square?
-                    return builder.toByteArray();
-                }
-                bits = _decodeBase64Escape(b64variant, ch, 0);
-                if (bits < 0) { // white space to skip
-                    continue;
-                }
-            }
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
-                        builder.append(decodedData);
-                        return builder.toByteArray();
-                    }
-                    bits = _decodeBase64Escape(b64variant, ch, 2);
-                }
-                if (bits == Base64Variant.BASE64_VALUE_PADDING) {
-                    // Ok, must get more padding chars, then
-                    if (_inputPtr >= _inputEnd) {
-                        _loadMoreGuaranteed();
-                    }
-                    ch = _inputBuffer[_inputPtr++];
-                    if (!b64variant.usesPaddingChar(ch)) {
-                        throw reportInvalidBase64Char(b64variant, ch, 3, "expected padding character '"+b64variant.getPaddingChar()+"'");
-                    }
-                    // Got 12 bits, only need 8, need to shift
-                    decodedData >>= 4;
-                    builder.append(decodedData);
-                    continue;
-                }
-                // otherwise we got escaped other char, to be processed below
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
-                        builder.appendTwoBytes(decodedData);
-                        return builder.toByteArray();
-                    }
-                    bits = _decodeBase64Escape(b64variant, ch, 3);
-                }
-                if (bits == Base64Variant.BASE64_VALUE_PADDING) {
-                    // With padding we only get 2 bytes; but we have
-                    // to shift it a bit so it is identical to triplet
-                    // case with partial output.
-                    // 3 chars gives 3x6 == 18 bits, of which 2 are
-                    // dummies, need to discard:
-                    decodedData >>= 2;
-                    builder.appendTwoBytes(decodedData);
-                    continue;
-                }
-                // otherwise we got escaped other char, to be processed below
-            }
-            // otherwise, our triplet is now complete
-            decodedData = (decodedData << 6) | bits;
-            builder.appendThreeBytes(decodedData);
-        }
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
-        if (i == INT_RBRACKET) {
-            _updateLocation();
-            if (!_parsingContext.inArray()) {
-                _reportMismatchedEndMarker(i, '}');
-            }
-            _parsingContext = _parsingContext.clearAndGetParent();
-            _currToken = JsonToken.END_ARRAY;
-        }
-        if (i == INT_RCURLY) {
-            _updateLocation();
-            if (!_parsingContext.inObject()) {
-                _reportMismatchedEndMarker(i, ']');
-            }
-            _parsingContext = _parsingContext.clearAndGetParent();
-            _currToken = JsonToken.END_OBJECT;
-        }
-    }
-}
diff --git a/src/main/java/com/fasterxml/jackson/core/json/UTF8DataInputJsonParser.java b/src/main/java/com/fasterxml/jackson/core/json/UTF8DataInputJsonParser.java
deleted file mode 100644
index 7881b48c..00000000
--- a/src/main/java/com/fasterxml/jackson/core/json/UTF8DataInputJsonParser.java
+++ /dev/null
@@ -1,2852 +0,0 @@
-package com.fasterxml.jackson.core.json;
-
-import java.io.*;
-import java.util.Arrays;
-
-import com.fasterxml.jackson.core.*;
-import com.fasterxml.jackson.core.base.ParserBase;
-import com.fasterxml.jackson.core.io.CharTypes;
-import com.fasterxml.jackson.core.io.IOContext;
-import com.fasterxml.jackson.core.sym.ByteQuadsCanonicalizer;
-import com.fasterxml.jackson.core.util.*;
-
-import static com.fasterxml.jackson.core.JsonTokenId.*;
-
-/**
- * This is a concrete implementation of {@link JsonParser}, which is
- * based on a {@link java.io.DataInput} as the input source.
- *<p>
- * Due to limitations in look-ahead (basically there's none), as well
- * as overhead of reading content mostly byte-by-byte,
- * there are some
- * minor differences from regular streaming parsing. Specifically:
- *<ul>
- * <li>Input location is not being tracked, as offsets would need to
- *   be updated for each read from all over the place; if caller wants
- *   this information, it has to track this with {@link DataInput}.
- *  </li>
- * <li>As a consequence linefeed handling is removed so all white-space is
- *    equal; and checks are simplified NOT to check for control characters
- *  </li>
- * </ul>
- *
- * @since 2.8
- */
-public class UTF8DataInputJsonParser
-    extends ParserBase
-{
-    final static byte BYTE_LF = (byte) '\n';
-
-    // This is the main input-code lookup table, fetched eagerly
-    private final static int[] _icUTF8 = CharTypes.getInputCodeUtf8();
-
-    // Latin1 encoding is not supported, but we do use 8-bit subset for
-    // pre-processing task, to simplify first pass, keep it fast.
-    protected final static int[] _icLatin1 = CharTypes.getInputCodeLatin1();
-
-    /*
-    /**********************************************************
-    /* Configuration
-    /**********************************************************
-     */
-
-    /**
-     * Codec used for data binding when (if) requested; typically full
-     * <code>ObjectMapper</code>, but that abstract is not part of core
-     * package.
-     */
-    protected ObjectCodec _objectCodec;
-
-    /**
-     * Symbol table that contains field names encountered so far
-     */
-    final protected ByteQuadsCanonicalizer _symbols;
-
-    /*
-    /**********************************************************
-    /* Parsing state
-    /**********************************************************
-     */
-
-    /**
-     * Temporary buffer used for name parsing.
-     */
-    protected int[] _quadBuffer = new int[16];
-
-    /**
-     * Flag that indicates that the current token has not yet
-     * been fully processed, and needs to be finished for
-     * some access (or skipped to obtain the next token)
-     */
-    protected boolean _tokenIncomplete;
-
-    /**
-     * Temporary storage for partially parsed name bytes.
-     */
-    private int _quad1;
-
-    /*
-    /**********************************************************
-    /* Current input data
-    /**********************************************************
-     */
-
-    protected DataInput _inputData;
-
-    /**
-     * Sometimes we need buffering for just a single byte we read but
-     * have to "push back"
-     */
-    protected int _nextByte = -1;
-
-    /*
-    /**********************************************************
-    /* Life-cycle
-    /**********************************************************
-     */
-
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
-
-    @Override
-    public ObjectCodec getCodec() {
-        return _objectCodec;
-    }
-
-    @Override
-    public void setCodec(ObjectCodec c) {
-        _objectCodec = c;
-    }
-
-    /*
-    /**********************************************************
-    /* Overrides for life-cycle
-    /**********************************************************
-     */
-
-    @Override
-    public int releaseBuffered(OutputStream out) throws IOException {
-        return 0;
-    }
-
-    @Override
-    public Object getInputSource() {
-        return _inputData;
-    }
-
-    /*
-    /**********************************************************
-    /* Overrides, low-level reading
-    /**********************************************************
-     */
-
-    @Override
-    protected void _closeInput() throws IOException { }
-
-    /**
-     * Method called to release internal buffers owned by the base
-     * reader. This may be called along with {@link #_closeInput} (for
-     * example, when explicitly closing this reader instance), or
-     * separately (if need be).
-     */
-    @Override
-    protected void _releaseBuffers() throws IOException
-    {
-        super._releaseBuffers();
-        // Merge found symbols, if any:
-        _symbols.release();
-    }
-
-    /*
-    /**********************************************************
-    /* Public API, data access
-    /**********************************************************
-     */
-
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
-
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
-
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
-
-    @Override
-    public String getValueAsString(String defValue) throws IOException
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
-        return super.getValueAsString(defValue);
-    }
-
-    @Override
-    public int getValueAsInt() throws IOException
-    {
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
-
-    @Override
-    public int getValueAsInt(int defValue) throws IOException
-    {
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
-                    }
-                    name.getChars(0, nameLen, _nameCopyBuffer, 0);
-                    _nameCopied = true;
-                }
-                return _nameCopyBuffer;
-    
-            case ID_STRING:
-                if (_tokenIncomplete) {
-                    _tokenIncomplete = false;
-                    _finishString(); // only strings can be incomplete
-                }
-                // fall through
-            case ID_NUMBER_INT:
-            case ID_NUMBER_FLOAT:
-                return _textBuffer.getTextBuffer();
-                
-            default:
-                return _currToken.asCharArray();
-            }
-        }
-        return null;
-    }
-
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
-            }
-            return _currToken.asCharArray().length;
-        }
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
-        }
-        return 0;
-    }
-    
-    @Override
-    public byte[] getBinaryValue(Base64Variant b64variant) throws IOException
-    {
-        if (_currToken != JsonToken.VALUE_STRING &&
-                (_currToken != JsonToken.VALUE_EMBEDDED_OBJECT || _binaryValue == null)) {
-            _reportError("Current token ("+_currToken+") not VALUE_STRING or VALUE_EMBEDDED_OBJECT, can not access as binary");
-        }
-        /* To ensure that we won't see inconsistent data, better clear up
-         * state...
-         */
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
-        }
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
-        }
-        // otherwise do "real" incremental parsing...
-        byte[] buf = _ioContext.allocBase64Buffer();
-        try {
-            return _readBinary(b64variant, out, buf);
-        } finally {
-            _ioContext.releaseBase64Buffer(buf);
-        }
-    }
-
-    protected int _readBinary(Base64Variant b64variant, OutputStream out,
-                              byte[] buffer) throws IOException
-    {
-        int outputPtr = 0;
-        final int outputEnd = buffer.length - 3;
-        int outputCount = 0;
-
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
-            ch = _inputData.readUnsignedByte();
-            bits = b64variant.decodeBase64Char(ch);
-            if (bits < 0) {
-                bits = _decodeBase64Escape(b64variant, ch, 1);
-            }
-            decodedData = (decodedData << 6) | bits;
-
-            // third base64 char; can be padding, but not ws
-            ch = _inputData.readUnsignedByte();
-            bits = b64variant.decodeBase64Char(ch);
-
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
-                }
-            }
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
-    {
-        /* First: field names are special -- we will always tokenize
-         * (part of) value along with field name to simplify
-         * state handling. If so, can and need to use secondary token:
-         */
-        if (_currToken == JsonToken.FIELD_NAME) {
-            return _nextAfterName();
-        }
-        // But if we didn't already have a name, and (partially?) decode number,
-        // need to ensure no numeric information is leaked
-        _numTypesValid = NR_UNKNOWN;
-        if (_tokenIncomplete) {
-            _skipString(); // only strings can be partial
-        }
-        int i = _skipWSOrEnd();
-        if (i < 0) { // end-of-input
-            // Close/release things like input source, symbol table and recyclable buffers
-            close();
-            return (_currToken = null);
-        }
-        // clear any data retained so far
-        _binaryValue = null;
-        _tokenInputRow = _currInputRow;
-
-        // Closing scope?
-        if (i == INT_RBRACKET || i == INT_RCURLY) {
-            _closeScope(i);
-            return _currToken;
-        }
-
-        // Nope: do we then expect a comma?
-        if (_parsingContext.expectComma()) {
-            if (i != INT_COMMA) {
-                _reportUnexpectedChar(i, "was expecting comma to separate "+_parsingContext.typeDesc()+" entries");
-            }
-            i = _skipWS();
-
-            // Was that a trailing comma?
-            if (Feature.ALLOW_TRAILING_COMMA.enabledIn(_features)) {
-                if (i == INT_RBRACKET || i == INT_RCURLY) {
-                    _closeScope(i);
-                    return _currToken;
-                }
-            }
-        }
-
-        /* And should we now have a name? Always true for
-         * Object contexts, since the intermediate 'expect-value'
-         * state is never retained.
-         */
-        if (!_parsingContext.inObject()) {
-            return _nextTokenNotInObject(i);
-        }
-        // So first parse the field name itself:
-        String n = _parseName(i);
-        _parsingContext.setCurrentName(n);
-        _currToken = JsonToken.FIELD_NAME;
-
-        i = _skipColon();
-
-        // Ok: we must have a value... what is it? Strings are very common, check first:
-        if (i == INT_QUOTE) {
-            _tokenIncomplete = true;
-            _nextToken = JsonToken.VALUE_STRING;
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
-        return nameStr;
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
-    public Boolean nextBooleanValue() throws IOException
-    {
-        // two distinct cases; either got name and we know next type, or 'other'
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
-            }
-            if (t == JsonToken.START_ARRAY) {
-                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
-            } else if (t == JsonToken.START_OBJECT) {
-                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
-            }
-            return null;
-        }
-
-        JsonToken t = nextToken();
-        if (t == JsonToken.VALUE_TRUE) {
-            return Boolean.TRUE;
-        }
-        if (t == JsonToken.VALUE_FALSE) {
-            return Boolean.FALSE;
-        }
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
-    protected JsonToken _parsePosNumber(int c) throws IOException
-    {
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
-            }
-        } else {
-            outBuf[0] = (char) c;
-            c = _inputData.readUnsignedByte();
-            outPtr = 1;
-        }
-        int intLen = outPtr;
-
-        // With this, we have a nice and tight loop:
-        while (c <= INT_9 && c >= INT_0) {
-            ++intLen;
-            outBuf[outPtr++] = (char) c;
-            c = _inputData.readUnsignedByte();
-        }
-        if (c == '.' || c == 'e' || c == 'E') {
-            return _parseFloat(outBuf, outPtr, c, false, intLen);
-        }
-        _textBuffer.setCurrentLength(outPtr);
-        // As per [core#105], need separating space between root values; check here
-        if (_parsingContext.inRoot()) {
-            _verifyRootSpace();
-        } else {
-            _nextByte = c;
-        }
-        // And there we have it!
-        return resetInt(false, intLen);
-    }
-    
-    protected JsonToken _parseNegNumber() throws IOException
-    {
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
-            }
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
-        }
-        if (c == '.' || c == 'e' || c == 'E') {
-            return _parseFloat(outBuf, outPtr, c, true, intLen);
-        }
-        _textBuffer.setCurrentLength(outPtr);
-        // As per [core#105], need separating space between root values; check here
-        _nextByte = c;
-        if (_parsingContext.inRoot()) {
-            _verifyRootSpace();
-        }
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
-    {
-        int ch = _inputData.readUnsignedByte();
-        // if not followed by a number (probably '.'); return zero as is, to be included
-        if (ch < INT_0 || ch > INT_9) {
-            return ch;
-        }
-        // we may want to allow leading zeroes them, after all...
-        if (!isEnabled(Feature.ALLOW_NUMERIC_LEADING_ZEROS)) {
-            reportInvalidNumber("Leading zeroes not allowed");
-        }
-        // if so, just need to skip either all zeroes (if followed by number); or all but one (if non-number)
-        while (ch == INT_0) {
-            ch = _inputData.readUnsignedByte();
-        }
-        return ch;
-    }
-
-    private final JsonToken _parseFloat(char[] outBuf, int outPtr, int c,
-            boolean negative, int integerPartLength) throws IOException
-    {
-        int fractLen = 0;
-
-        // And then see if we get other parts
-        if (c == INT_PERIOD) { // yes, fraction
-            outBuf[outPtr++] = (char) c;
-
-            fract_loop:
-            while (true) {
-                c = _inputData.readUnsignedByte();
-                if (c < INT_0 || c > INT_9) {
-                    break fract_loop;
-                }
-                ++fractLen;
-                if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
-                    outPtr = 0;
-                }
-                outBuf[outPtr++] = (char) c;
-            }
-            // must be followed by sequence of ints, one minimum
-            if (fractLen == 0) {
-                reportUnexpectedNumberChar(c, "Decimal point not followed by a digit");
-            }
-        }
-
-        int expLen = 0;
-        if (c == INT_e || c == INT_E) { // exponent?
-            if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
-                outPtr = 0;
-            }
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
-            }
-            while (c <= INT_9 && c >= INT_0) {
-                ++expLen;
-                if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
-                    outPtr = 0;
-                }
-                outBuf[outPtr++] = (char) c;
-                c = _inputData.readUnsignedByte();
-            }
-            // must be followed by sequence of ints, one minimum
-            if (expLen == 0) {
-                reportUnexpectedNumberChar(c, "Exponent indicator not followed by a digit");
-            }
-        }
-
-        // Ok; unless we hit end-of-input, need to push last char read back
-        // As per #105, need separating space between root values; check here
-        _nextByte = c;
-        if (_parsingContext.inRoot()) {
-            _verifyRootSpace();
-        }
-        _textBuffer.setCurrentLength(outPtr);
-
-        // And there we have it!
-        return resetFloat(negative, integerPartLength, fractLen, expLen);
-    }
-
-    /**
-     * Method called to ensure that a root-value is followed by a space token,
-     * if possible.
-     *<p>
-     * NOTE: with {@link DataInput} source, not really feasible, up-front.
-     * If we did want, we could rearrange things to require space before
-     * next read, but initially let's just do nothing.
-     */
-    private final void _verifyRootSpace() throws IOException
-    {
-        int ch = _nextByte;
-        if (ch <= INT_SPACE) {
-            _nextByte = -1;
-            if (ch == INT_CR || ch == INT_LF) {
-                ++_currInputRow;
-            }
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
-    protected final String _parseName(int i) throws IOException
-    {
-        if (i != INT_QUOTE) {
-            return _handleOddName(i);
-        }
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
-                }
-                return parseName(q, i, 2);
-            }
-            if (i == INT_QUOTE) { // one byte/char case or broken
-                return findName(q, 1);
-            }
-            return parseName(q, i, 1);
-        }     
-        if (q == INT_QUOTE) { // special case, ""
-            return "";
-        }
-        return parseName(0, q, 0); // quoting or invalid char
-    }
-
-    private final String _parseMediumName(int q2) throws IOException
-    {
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
-            }
-            return parseName(_quad1, q2, i, 2);
-        }
-        q2 = (q2 << 8) | i;
-        i = _inputData.readUnsignedByte();
-        if (codes[i] != 0) {
-            if (i == INT_QUOTE) { // 7 bytes
-                return findName(_quad1, q2, 3);
-            }
-            return parseName(_quad1, q2, i, 3);
-        }
-        q2 = (q2 << 8) | i;
-        i = _inputData.readUnsignedByte();
-        if (codes[i] != 0) {
-            if (i == INT_QUOTE) { // 8 bytes
-                return findName(_quad1, q2, 4);
-            }
-            return parseName(_quad1, q2, i, 4);
-        }
-        return _parseMediumName2(i, q2);
-    }
-
-    private final String _parseMediumName2(int q3, final int q2) throws IOException
-    {
-        final int[] codes = _icLatin1;
-
-        // Got 9 name bytes so far
-        int i = _inputData.readUnsignedByte();
-        if (codes[i] != 0) {
-            if (i == INT_QUOTE) { // 9 bytes
-                return findName(_quad1, q2, q3, 1);
-            }
-            return parseName(_quad1, q2, q3, i, 1);
-        }
-        q3 = (q3 << 8) | i;
-        i = _inputData.readUnsignedByte();
-        if (codes[i] != 0) {
-            if (i == INT_QUOTE) { // 10 bytes
-                return findName(_quad1, q2, q3, 2);
-            }
-            return parseName(_quad1, q2, q3, i, 2);
-        }
-        q3 = (q3 << 8) | i;
-        i = _inputData.readUnsignedByte();
-        if (codes[i] != 0) {
-            if (i == INT_QUOTE) { // 11 bytes
-                return findName(_quad1, q2, q3, 3);
-            }
-            return parseName(_quad1, q2, q3, i, 3);
-        }
-        q3 = (q3 << 8) | i;
-        i = _inputData.readUnsignedByte();
-        if (codes[i] != 0) {
-            if (i == INT_QUOTE) { // 12 bytes
-                return findName(_quad1, q2, q3, 4);
-            }
-            return parseName(_quad1, q2, q3, i, 4);
-        }
-        return _parseLongName(i, q2, q3);
-    }
-    
-    private final String _parseLongName(int q, final int q2, int q3) throws IOException
-    {
-        _quadBuffer[0] = _quad1;
-        _quadBuffer[1] = q2;
-        _quadBuffer[2] = q3;
-
-        // As explained above, will ignore UTF-8 encoding at this point
-        final int[] codes = _icLatin1;
-        int qlen = 3;
-
-        while (true) {
-            int i = _inputData.readUnsignedByte();
-            if (codes[i] != 0) {
-                if (i == INT_QUOTE) {
-                    return findName(_quadBuffer, qlen, q, 1);
-                }
-                return parseEscapedName(_quadBuffer, qlen, q, i, 1);
-            }
-
-            q = (q << 8) | i;
-            i = _inputData.readUnsignedByte();
-            if (codes[i] != 0) {
-                if (i == INT_QUOTE) {
-                    return findName(_quadBuffer, qlen, q, 2);
-                }
-                return parseEscapedName(_quadBuffer, qlen, q, i, 2);
-            }
-
-            q = (q << 8) | i;
-            i = _inputData.readUnsignedByte();
-            if (codes[i] != 0) {
-                if (i == INT_QUOTE) {
-                    return findName(_quadBuffer, qlen, q, 3);
-                }
-                return parseEscapedName(_quadBuffer, qlen, q, i, 3);
-            }
-
-            q = (q << 8) | i;
-            i = _inputData.readUnsignedByte();
-            if (codes[i] != 0) {
-                if (i == INT_QUOTE) {
-                    return findName(_quadBuffer, qlen, q, 4);
-                }
-                return parseEscapedName(_quadBuffer, qlen, q, i, 4);
-            }
-
-            // Nope, no end in sight. Need to grow quad array etc
-            if (qlen >= _quadBuffer.length) {
-                _quadBuffer = _growArrayBy(_quadBuffer, qlen);
-            }
-            _quadBuffer[qlen++] = q;
-            q = i;
-        }
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
-     */
-    protected final String parseEscapedName(int[] quads, int qlen, int currQuad, int ch,
-            int currQuadBytes) throws IOException
-    {
-        /* 25-Nov-2008, tatu: This may seem weird, but here we do not want to worry about
-         *   UTF-8 decoding yet. Rather, we'll assume that part is ok (if not it will get
-         *   caught later on), and just handle quotes and backslashes here.
-         */
-        final int[] codes = _icLatin1;
-
-        while (true) {
-            if (codes[ch] != 0) {
-                if (ch == INT_QUOTE) { // we are done
-                    break;
-                }
-                // Unquoted white space?
-                if (ch != INT_BACKSLASH) {
-                    // As per [JACKSON-208], call can now return:
-                    _throwUnquotedSpace(ch, "name");
-                } else {
-                    // Nope, escape sequence
-                    ch = _decodeEscaped();
-                }
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
-                    }
-                    // And same last byte in both cases, gets output below:
-                    ch = 0x80 | (ch & 0x3f);
-                }
-            }
-            // Ok, we have one more byte to add at any rate:
-            if (currQuadBytes < 4) {
-                ++currQuadBytes;
-                currQuad = (currQuad << 8) | ch;
-            } else {
-                if (qlen >= quads.length) {
-                    _quadBuffer = quads = _growArrayBy(quads, quads.length);
-                }
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
-            }
-            quads[qlen++] = pad(currQuad, currQuadBytes);
-        }
-        String name = _symbols.findName(quads, qlen);
-        if (name == null) {
-            name = addName(quads, qlen, currQuadBytes);
-        }
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
-    {
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
-        }
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
-                }
-                quads[qlen++] = currQuad;
-                currQuad = ch;
-                currQuadBytes = 1;
-            }
-            ch = _inputData.readUnsignedByte();
-            if (codes[ch] != 0) {
-                break;
-            }
-        }
-        // Note: we must "push back" character read here for future consumption
-        _nextByte = ch;
-        if (currQuadBytes > 0) {
-            if (qlen >= quads.length) {
-                _quadBuffer = quads = _growArrayBy(quads, quads.length);
-            }
-            quads[qlen++] = currQuad;
-        }
-        String name = _symbols.findName(quads, qlen);
-        if (name == null) {
-            name = addName(quads, qlen, currQuadBytes);
-        }
-        return name;
-    }
-
-    /* Parsing to allow optional use of non-standard single quotes.
-     * Plenty of duplicated code;
-     * main reason being to try to avoid slowing down fast path
-     * for valid JSON -- more alternatives, more code, generally
-     * bit slower execution.
-     */
-    protected String _parseAposName() throws IOException
-    {
-        int ch = _inputData.readUnsignedByte();
-        if (ch == '\'') { // special case, ''
-            return "";
-        }
-        int[] quads = _quadBuffer;
-        int qlen = 0;
-        int currQuad = 0;
-        int currQuadBytes = 0;
-
-        // Copied from parseEscapedFieldName, with minor mods:
-
-        final int[] codes = _icLatin1;
-
-        while (true) {
-            if (ch == '\'') {
-                break;
-            }
-            // additional check to skip handling of double-quotes
-            if (ch != '"' && codes[ch] != 0) {
-                if (ch != '\\') {
-                    // Unquoted white space?
-                    // As per [JACKSON-208], call can now return:
-                    _throwUnquotedSpace(ch, "name");
-                } else {
-                    // Nope, escape sequence
-                    ch = _decodeEscaped();
-                }
-                /* Oh crap. May need to UTF-8 (re-)encode it, if it's  beyond
-                 * 7-bit ASCII. Gets pretty messy. If this happens often, may want
-                 * to use different name canonicalization to avoid these hits.
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
-                    }
-                    // And same last byte in both cases, gets output below:
-                    ch = 0x80 | (ch & 0x3f);
-                }
-            }
-            // Ok, we have one more byte to add at any rate:
-            if (currQuadBytes < 4) {
-                ++currQuadBytes;
-                currQuad = (currQuad << 8) | ch;
-            } else {
-                if (qlen >= quads.length) {
-                    _quadBuffer = quads = _growArrayBy(quads, quads.length);
-                }
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
-            }
-            quads[qlen++] = pad(currQuad, currQuadBytes);
-        }
-        String name = _symbols.findName(quads, qlen);
-        if (name == null) {
-            name = addName(quads, qlen, currQuadBytes);
-        }
-        return name;
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
-    {
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
-        }
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
-    {
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
-
-    private String _finishAndReturnString() throws IOException
-    {
-        int outPtr = 0;
-        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
-        final int[] codes = _icUTF8;
-        final int outEnd = outBuf.length;
-
-        do {
-            int c = _inputData.readUnsignedByte();
-            if (codes[c] != 0) {
-                if (c == INT_QUOTE) {
-                    return _textBuffer.setCurrentAndReturn(outPtr);
-                }
-                _finishString2(outBuf, outPtr, c);
-                return _textBuffer.contentsAsString();
-            }
-            outBuf[outPtr++] = (char) c;
-        } while (outPtr < outEnd);
-        _finishString2(outBuf, outPtr, _inputData.readUnsignedByte());
-        return _textBuffer.contentsAsString();
-    }
-    
-    private final void _finishString2(char[] outBuf, int outPtr, int c)
-        throws IOException
-    {
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
-            }
-            // Ok: end marker, escape or multi-byte?
-            if (c == INT_QUOTE) {
-                break main_loop;
-            }
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
-            }
-            // Need more room?
-            if (outPtr >= outBuf.length) {
-                outBuf = _textBuffer.finishCurrentSegment();
-                outPtr = 0;
-                outEnd = outBuf.length;
-            }
-            // Ok, let's add char to output:
-            outBuf[outPtr++] = (char) c;
-        }
-        _textBuffer.setCurrentLength(outPtr);
-    }
-
-    /**
-     * Method called to skim through rest of unparsed String value,
-     * if it is not needed. This can be done bit faster if contents
-     * need not be stored for future access.
-     */
-    protected void _skipString() throws IOException
-    {
-        _tokenIncomplete = false;
-
-        // Need to be fully UTF-8 aware here:
-        final int[] codes = _icUTF8;
-
-        main_loop:
-        while (true) {
-            int c;
-
-            ascii_loop:
-            while (true) {
-                c = _inputData.readUnsignedByte();
-                if (codes[c] != 0) {
-                    break ascii_loop;
-                }
-            }
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
-                break;
-            default:
-                if (c < INT_SPACE) {
-                    _throwUnquotedSpace(c, "string value");
-                } else {
-                    // Is this good enough error message?
-                    _reportInvalidChar(c);
-                }
-            }
-        }
-    }
-
-    /**
-     * Method for handling cases where first non-space character
-     * of an expected value token is not legal for standard JSON content.
-     */
-    protected JsonToken _handleUnexpectedValue(int c)
-        throws IOException
-    {
-        // Most likely an error, unless we are to allow single-quote-strings
-        switch (c) {
-        case ']':
-            if (!_parsingContext.inArray()) {
-                break;
-            }
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
-            if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
-                return resetAsNaN("Infinity", Double.POSITIVE_INFINITY);
-            }
-            _reportError("Non-standard token 'Infinity': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
-            break;
-        case '+': // note: '-' is taken as number
-            return _handleInvalidNumberStart(_inputData.readUnsignedByte(), false);
-        }
-        // [core#77] Try to decode most likely token
-        if (Character.isJavaIdentifierStart(c)) {
-            _reportInvalidToken(c, ""+((char) c), "('true', 'false' or 'null')");
-        }
-        // but if it doesn't look like a token:
-        _reportUnexpectedChar(c, "expected a valid value (number, String, array, object, 'true', 'false' or 'null')");
-        return null;
-    }
-
-    protected JsonToken _handleApos() throws IOException
-    {
-        int c = 0;
-        // Otherwise almost verbatim copy of _finishString()
-        int outPtr = 0;
-        char[] outBuf = _textBuffer.emptyAndGetCurrentSegment();
-
-        // Here we do want to do full decoding, hence:
-        final int[] codes = _icUTF8;
-
-        main_loop:
-        while (true) {
-            // Then the tight ascii non-funny-char loop:
-            ascii_loop:
-            while (true) {
-                int outEnd = outBuf.length;
-                if (outPtr >= outBuf.length) {
-                    outBuf = _textBuffer.finishCurrentSegment();
-                    outPtr = 0;
-                    outEnd = outBuf.length;
-                }
-                do {
-                    c = _inputData.readUnsignedByte();
-                    if (c == '\'') {
-                        break main_loop;
-                    }
-                    if (codes[c] != 0) {
-                        break ascii_loop;
-                    }
-                    outBuf[outPtr++] = (char) c;
-                } while (outPtr < outEnd);
-            }
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
-                }
-                /*
-                if ((i != INT_SPACE) && (i != INT_LF) && (i != INT_CR)) {
-                    _throwInvalidSpace(i);
-                }
-                */
-            }
-            i = _inputData.readUnsignedByte();
-        }        
-    }
-
-    private final int _skipColon() throws IOException
-    {
-        int i = _nextByte;
-        if (i < 0) {
-            i = _inputData.readUnsignedByte();
-        } else {
-            _nextByte = -1;
-        }
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
-        }
-        if (i == INT_SPACE || i == INT_TAB) {
-            i = _inputData.readUnsignedByte();
-        }
-        if (i == INT_COLON) {
-            i = _inputData.readUnsignedByte();
-            if (i > INT_SPACE) {
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
-                }
-                gotColon = true;
-            } else {
-                // 06-May-2016, tatu: Could verify validity of WS, but for now why bother.
-                //   ... but line number is useful thingy
-                if (i == INT_CR || i == INT_LF) {
-                    ++_currInputRow;
-                }
-            }
-        }
-    }
-
-    private final void _skipComment() throws IOException
-    {
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
-
-    private final void _skipCComment() throws IOException
-    {
-        // Need to be UTF-8 aware here to decode content (for skipping)
-        final int[] codes = CharTypes.getInputCodeComment();
-        int i = _inputData.readUnsignedByte();
-
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
-                }
-            }
-            i = _inputData.readUnsignedByte();
-        }
-    }
-
-    private final boolean _skipYAMLComment() throws IOException
-    {
-        if (!isEnabled(Feature.ALLOW_YAML_COMMENTS)) {
-            return false;
-        }
-        _skipLine();
-        return true;
-    }
-
-    /**
-     * Method for skipping contents of an input line; usually for CPP
-     * and YAML style comments.
-     */
-    private final void _skipLine() throws IOException
-    {
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
-        }
-    }
-    
-    @Override
-    protected char _decodeEscaped() throws IOException
-    {
-        int c = _inputData.readUnsignedByte();
-
-        switch (c) {
-            // First, ones that are mapped
-        case 'b':
-            return '\b';
-        case 't':
-            return '\t';
-        case 'n':
-            return '\n';
-        case 'f':
-            return '\f';
-        case 'r':
-            return '\r';
-
-            // And these are to be returned as they are
-        case '"':
-        case '/':
-        case '\\':
-            return (char) c;
-
-        case 'u': // and finally hex-escaped
-            break;
-
-        default:
-            return _handleUnrecognizedCharacterEscape((char) _decodeCharForError(c));
-        }
-
-        // Ok, a hex escape. Need 4 characters
-        int value = 0;
-        for (int i = 0; i < 4; ++i) {
-            int ch = _inputData.readUnsignedByte();
-            int digit = CharTypes.charToHex(ch);
-            if (digit < 0) {
-                _reportUnexpectedChar(ch, "expected a hex-digit for character escape sequence");
-            }
-            value = (value << 4) | digit;
-        }
-        return (char) value;
-    }
-
-    protected int _decodeCharForError(int firstByte) throws IOException
-    {
-        int c = firstByte & 0xFF;
-        if (c > 0x7F) { // if >= 0, is ascii and fine as is
-            int needed;
-            
-            // Ok; if we end here, we got multi-byte combination
-            if ((c & 0xE0) == 0xC0) { // 2 bytes (0x0080 - 0x07FF)
-                c &= 0x1F;
-                needed = 1;
-            } else if ((c & 0xF0) == 0xE0) { // 3 bytes (0x0800 - 0xFFFF)
-                c &= 0x0F;
-                needed = 2;
-            } else if ((c & 0xF8) == 0xF0) {
-                // 4 bytes; double-char with surrogates and all...
-                c &= 0x07;
-                needed = 3;
-            } else {
-                _reportInvalidInitial(c & 0xFF);
-                needed = 1; // never gets here
-            }
-
-            int d = _inputData.readUnsignedByte();
-            if ((d & 0xC0) != 0x080) {
-                _reportInvalidOther(d & 0xFF);
-            }
-            c = (c << 6) | (d & 0x3F);
-            
-            if (needed > 1) { // needed == 1 means 2 bytes total
-                d = _inputData.readUnsignedByte(); // 3rd byte
-                if ((d & 0xC0) != 0x080) {
-                    _reportInvalidOther(d & 0xFF);
-                }
-                c = (c << 6) | (d & 0x3F);
-                if (needed > 2) { // 4 bytes? (need surrogates)
-                    d = _inputData.readUnsignedByte();
-                    if ((d & 0xC0) != 0x080) {
-                        _reportInvalidOther(d & 0xFF);
-                    }
-                    c = (c << 6) | (d & 0x3F);
-                }
-            }
-        }
-        return c;
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
-     * Efficient handling for incremental parsing of base64-encoded
-     * textual content.
-     */
-    @SuppressWarnings("resource")
-    protected final byte[] _decodeBase64(Base64Variant b64variant) throws IOException
-    {
-        ByteArrayBuilder builder = _getByteArrayBuilder();
-
-        //main_loop:
-        while (true) {
-            // first, we'll skip preceding white space, if any
-            int ch;
-            do {
-                ch = _inputData.readUnsignedByte();
-            } while (ch <= INT_SPACE);
-            int bits = b64variant.decodeBase64Char(ch);
-            if (bits < 0) { // reached the end, fair and square?
-                if (ch == INT_QUOTE) {
-                    return builder.toByteArray();
-                }
-                bits = _decodeBase64Escape(b64variant, ch, 0);
-                if (bits < 0) { // white space to skip
-                    continue;
-                }
-            }
-            int decodedData = bits;
-            
-            // then second base64 char; can't get padding yet, nor ws
-            ch = _inputData.readUnsignedByte();
-            bits = b64variant.decodeBase64Char(ch);
-            if (bits < 0) {
-                bits = _decodeBase64Escape(b64variant, ch, 1);
-            }
-            decodedData = (decodedData << 6) | bits;
-            // third base64 char; can be padding, but not ws
-            ch = _inputData.readUnsignedByte();
-            bits = b64variant.decodeBase64Char(ch);
-
-            // First branch: can get padding (-> 1 byte)
-            if (bits < 0) {
-                if (bits != Base64Variant.BASE64_VALUE_PADDING) {
-                    // could also just be 'missing'  padding
-                    if (ch == '"' && !b64variant.usesPadding()) {
-                        decodedData >>= 4;
-                        builder.append(decodedData);
-                        return builder.toByteArray();
-                    }
-                    bits = _decodeBase64Escape(b64variant, ch, 2);
-                }
-                if (bits == Base64Variant.BASE64_VALUE_PADDING) {
-                    ch = _inputData.readUnsignedByte();
-                    if (!b64variant.usesPaddingChar(ch)) {
-                        throw reportInvalidBase64Char(b64variant, ch, 3, "expected padding character '"+b64variant.getPaddingChar()+"'");
-                    }
-                    // Got 12 bits, only need 8, need to shift
-                    decodedData >>= 4;
-                    builder.append(decodedData);
-                    continue;
-                }
-            }
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
-                        builder.appendTwoBytes(decodedData);
-                        return builder.toByteArray();
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
-                    builder.appendTwoBytes(decodedData);
-                    continue;
-                }
-            }
-            // otherwise, our triplet is now complete
-            decodedData = (decodedData << 6) | bits;
-            builder.appendThreeBytes(decodedData);
-        }
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
-        if (i == INT_RBRACKET) {
-            if (!_parsingContext.inArray()) {
-                _reportMismatchedEndMarker(i, '}');
-            }
-            _parsingContext = _parsingContext.clearAndGetParent();
-            _currToken = JsonToken.END_ARRAY;
-        }
-        if (i == INT_RCURLY) {
-            if (!_parsingContext.inObject()) {
-                _reportMismatchedEndMarker(i, ']');
-            }
-            _parsingContext = _parsingContext.clearAndGetParent();
-            _currToken = JsonToken.END_OBJECT;
-        }
-    }
-
-    /**
-     * Helper method needed to fix [Issue#148], masking of 0x00 character
-     */
-    private final static int pad(int q, int bytes) {
-        return (bytes == 4) ? q : (q | (-1 << (bytes << 3)));
-    }
-}
diff --git a/src/main/java/com/fasterxml/jackson/core/json/parsers/JsonParserFromReader.java b/src/main/java/com/fasterxml/jackson/core/json/parsers/JsonParserFromReader.java
new file mode 100644
index 00000000..0466e2f2
--- /dev/null
+++ b/src/main/java/com/fasterxml/jackson/core/json/parsers/JsonParserFromReader.java
@@ -0,0 +1,2700 @@
+package com.fasterxml.jackson.core.json.parsers;
+
+import java.io.*;
+
+import com.fasterxml.jackson.core.*;
+import com.fasterxml.jackson.core.base.ParserBase;
+import com.fasterxml.jackson.core.io.CharTypes;
+import com.fasterxml.jackson.core.io.IOContext;
+import com.fasterxml.jackson.core.sym.CharsToNameCanonicalizer;
+import com.fasterxml.jackson.core.util.*;
+
+import static com.fasterxml.jackson.core.JsonTokenId.*;
+
+/**
+ * This is a concrete implementation of {@link JsonParser}, which is
+ * based on a {@link java.io.Reader} to handle low-level character
+ * conversion tasks.
+ */
+public class JsonParserFromReader // final in 2.3, earlier
+    extends ParserBase
+{
+    protected final static int FEAT_MASK_TRAILING_COMMA = Feature.ALLOW_TRAILING_COMMA.getMask();
+
+    // Latin1 encoding is not supported, but we do use 8-bit subset for
+    // pre-processing task, to simplify first pass, keep it fast.
+    protected final static int[] _icLatin1 = CharTypes.getInputCodeLatin1();
+
+    /*
+    /**********************************************************
+    /* Input configuration
+    /**********************************************************
+     */
+
+    /**
+     * Reader that can be used for reading more content, if one
+     * buffer from input source, but in some cases pre-loaded buffer
+     * is handed to the parser.
+     */
+    protected Reader _reader;
+
+    /**
+     * Current buffer from which data is read; generally data is read into
+     * buffer from input source.
+     */
+    protected char[] _inputBuffer;
+
+    /**
+     * Flag that indicates whether the input buffer is recycable (and
+     * needs to be returned to recycler once we are done) or not.
+     *<p>
+     * If it is not, it also means that parser can NOT modify underlying
+     * buffer.
+     */
+    protected boolean _bufferRecyclable;
+
+    /*
+    /**********************************************************
+    /* Configuration
+    /**********************************************************
+     */
+
+    protected ObjectCodec _objectCodec;
+
+    final protected CharsToNameCanonicalizer _symbols;
+
+    final protected int _hashSeed;
+
+    /*
+    /**********************************************************
+    /* Parsing state
+    /**********************************************************
+     */
+
+    /**
+     * Flag that indicates that the current token has not yet
+     * been fully processed, and needs to be finished for
+     * some access (or skipped to obtain the next token)
+     */
+    protected boolean _tokenIncomplete;
+
+    /**
+     * Value of {@link #_inputPtr} at the time when the first character of
+     * name token was read. Used for calculating token location when requested;
+     * combined with {@link #_currInputProcessed}, may be updated appropriately
+     * as needed.
+     *
+     * @since 2.7
+     */
+    protected long _nameStartOffset;
+
+    /**
+     * @since 2.7
+     */
+    protected int _nameStartRow;
+
+    /**
+     * @since 2.7
+     */
+    protected int _nameStartCol;
+
+    /*
+    /**********************************************************
+    /* Life-cycle
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Base method defs, overrides
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Low-level access, supporting
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Public API, data access
+    /**********************************************************
+     */
+
+    // // // Let's override default impls for improved performance
+
+    /*
+    /**********************************************************
+    /* Public API, traversal
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Public API, nextXxx() overrides
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Internal methods, number parsing
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Internal methods, secondary parsing
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Internal methods, other parsing
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Binary access
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Internal methods, location updating (refactored in 2.7)
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Error reporting
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Internal methods, other
+    /**********************************************************
+     */
+
+    @Override public void setCodec(ObjectCodec codecInstance) { _objectCodec = codecInstance; }@Override
+    public int releaseBufferedToWriter(Writer writerOut) throws IOException {
+        int numChars = _inputEnd - _inputPtr;
+        if (numChars < 1) { return 0; }
+        // let's just advance ptr to end
+        int originalIndex = _inputPtr;
+        writerOut.write(_inputBuffer, originalIndex, numChars);
+        return numChars;
+    }@Override
+    public int readBinaryValueToStream(Base64Variant base64Variant, OutputStream outputStream) throws IOException
+    {
+        // if we have already read the token, just use whatever we may have
+        if (!_tokenIncomplete || _currToken != JsonToken.VALUE_STRING) {
+            byte[] tmpBytes = getBinaryValue(base64Variant);
+            outputStream.write(tmpBytes);
+            return tmpBytes.length;
+        }
+        // otherwise do "real" incremental parsing...
+        byte[] charBuffer = _ioContext.allocBase64Buffer();
+        try {
+            return _readBinaryValue(base64Variant, outputStream, charBuffer);
+        } finally {
+            _ioContext.releaseBase64Buffer(charBuffer);
+        }
+    }// note: identical to one in UTF8StreamJsonParser
+    @Override
+    public final String nextStringValue() throws IOException
+    {
+        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
+            _nameCopied = false;
+            JsonToken token = _nextToken;
+            _nextToken = null;
+            _currToken = token;
+            if (token == JsonToken.VALUE_STRING) {
+                if (_tokenIncomplete) {
+                    _tokenIncomplete = false;
+                    _finishString();
+                }
+                return _textBuffer.contentsAsString();
+            }
+            if (token == JsonToken.START_ARRAY) {
+                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            } else if (token == JsonToken.START_OBJECT) {
+                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            }
+            return null;
+        }
+        // !!! TODO: optimize this case as well
+        return (nextJsonToken() == JsonToken.VALUE_STRING) ? getText() : null;
+    }// Implemented since 2.7
+    @Override
+    public boolean nextName(SerializableString serializableStringObj) throws IOException
+    {
+        // // // Note: most of code below is copied from nextToken()
+
+        _numTypesValid = NR_UNKNOWN;
+        if (_currToken == JsonToken.FIELD_NAME) {
+            _nextTokenAfterName();
+            return false;
+        }
+        if (_tokenIncomplete) {
+            _skipStringValue();
+        }
+        int index = _skipWhitespaceOrEnd();
+        if (index < 0) {
+            close();
+            _currToken = null;
+            return false;
+        }
+        _binaryValue = null;
+
+        // Closing scope?
+        if (index == INT_RBRACKET || index == INT_RCURLY) {
+            _closeContainer(index);
+            return false;
+        }
+
+        if (_parsingContext.expectComma()) {
+            index = _skipAfterComma(index);
+
+            // Was that a trailing comma?
+            if ((_features & FEAT_MASK_TRAILING_COMMA) != 0) {
+                if ((index == INT_RBRACKET) || (index == INT_RCURLY)) {
+                    _closeContainer(index);
+                    return false;
+                }
+            }
+        }
+
+        if (!_parsingContext.inObject()) {
+            _updateTokenLocation();
+            _nextTokenOutsideObject(index);
+            return false;
+        }
+
+        _updateNamePosition();
+        if (index == INT_QUOTE) {
+            // when doing literal match, must consider escaping:
+            char[] nameCharacters = serializableStringObj.asQuotedChars();
+            final int nameLength = nameCharacters.length;
+
+            // Require 4 more bytes for faster skipping of colon that follows name
+            if ((_inputPtr + nameLength + 4) < _inputEnd) { // maybe...
+                // first check length match by
+                final int limitIndex = _inputPtr+ nameLength;
+                if (_inputBuffer[limitIndex] == '"') {
+                    int bufferOffset = 0;
+                    int pointer = _inputPtr;
+                    while (true) {
+                        if (pointer == limitIndex) { // yes, match!
+                            _parsingContext.setCurrentName(serializableStringObj.getValue());
+                            _isNextFieldNameYes(_skipColonQuick(pointer +1));
+                            return true;
+                        }
+                        if (nameCharacters[bufferOffset] != _inputBuffer[pointer]) {
+                            break;
+                        }
+                        ++bufferOffset;
+                        ++pointer;
+                    }
+                }
+            }
+        }
+        return _isNextTokenNameMatch(index, serializableStringObj.getValue());
+    }@Override
+    public String nextName() throws IOException
+    {
+        // // // Note: this is almost a verbatim copy of nextToken() (minus comments)
+
+        _numTypesValid = NR_UNKNOWN;
+        if (_currToken == JsonToken.FIELD_NAME) {
+            _nextTokenAfterName();
+            return null;
+        }
+        if (_tokenIncomplete) {
+            _skipStringValue();
+        }
+        int index = _skipWhitespaceOrEnd();
+        if (index < 0) {
+            close();
+            _currToken = null;
+            return null;
+        }
+        _binaryValue = null;
+        if (index == INT_RBRACKET) {
+            _updateTokenLocation();
+            if (!_parsingContext.inArray()) {
+                _reportMismatchedEndMarker(index, '}');
+            }
+            _parsingContext = _parsingContext.clearAndGetParent();
+            _currToken = JsonToken.END_ARRAY;
+            return null;
+        }
+        if (index == INT_RCURLY) {
+            _updateTokenLocation();
+            if (!_parsingContext.inObject()) {
+                _reportMismatchedEndMarker(index, ']');
+            }
+            _parsingContext = _parsingContext.clearAndGetParent();
+            _currToken = JsonToken.END_OBJECT;
+            return null;
+        }
+        if (_parsingContext.expectComma()) {
+            index = _skipAfterComma(index);
+        }
+        if (!_parsingContext.inObject()) {
+            _updateTokenLocation();
+            _nextTokenOutsideObject(index);
+            return null;
+        }
+
+        _updateNamePosition();
+        String fieldName = (index == INT_QUOTE) ? _parseFieldName() : _handleOddFieldName(index);
+        _parsingContext.setCurrentName(fieldName);
+        _currToken = JsonToken.FIELD_NAME;
+        index = _skipColonAndReturnNext();
+
+        _updateTokenLocation();
+        if (index == INT_QUOTE) {
+            _tokenIncomplete = true;
+            _nextToken = JsonToken.VALUE_STRING;
+            return fieldName;
+        }
+
+        // Ok: we must have a value... what is it?
+
+        JsonToken token;
+
+        switch (index) {
+        case '-':
+            token = _parseNegativeNumber();
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
+            token = _parsePositiveNumber(index);
+            break;
+        case 'f':
+            _matchFalseLiteral();
+            token = JsonToken.VALUE_FALSE;
+            break;
+        case 'n':
+            _matchNullToken();
+            token = JsonToken.VALUE_NULL;
+            break;
+        case 't':
+            _matchTrueLiteral();
+            token = JsonToken.VALUE_TRUE;
+            break;
+        case '[':
+            token = JsonToken.START_ARRAY;
+            break;
+        case '{':
+            token = JsonToken.START_OBJECT;
+            break;
+        default:
+            token = _handleUnexpectedValue(index);
+            break;
+        }
+        _nextToken = token;
+        return fieldName;
+    }// note: identical to one in Utf8StreamParser
+    @Override
+    public final long nextLongOrDefault(long defaultInt) throws IOException
+    {
+        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
+            _nameCopied = false;
+            JsonToken token = _nextToken;
+            _nextToken = null;
+            _currToken = token;
+            if (token == JsonToken.VALUE_NUMBER_INT) {
+                return getLongValue();
+            }
+            if (token == JsonToken.START_ARRAY) {
+                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            } else if (token == JsonToken.START_OBJECT) {
+                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            }
+            return defaultInt;
+        }
+        // !!! TODO: optimize this case as well
+        return (nextJsonToken() == JsonToken.VALUE_NUMBER_INT) ? getLongValue() : defaultInt;
+    } /**
+     * @return Next token from the stream, if any found, or null
+     *   to indicate end-of-input
+     */
+    @Override
+    public final JsonToken nextJsonToken() throws IOException
+    {
+        /* First: field names are special -- we will always tokenize
+         * (part of) value along with field name to simplify
+         * state handling. If so, can and need to use secondary token:
+         */
+        if (_currToken == JsonToken.FIELD_NAME) {
+            return _nextTokenAfterName();
+        }
+        // But if we didn't already have a name, and (partially?) decode number,
+        // need to ensure no numeric information is leaked
+        _numTypesValid = NR_UNKNOWN;
+        if (_tokenIncomplete) {
+            _skipStringValue(); // only strings can be partial
+        }
+        int index = _skipWhitespaceOrEnd();
+        if (index < 0) { // end-of-input
+            // Should actually close/release things
+            // like input source, symbol table and recyclable buffers now.
+            close();
+            return (_currToken = null);
+        }
+        // clear any data retained so far
+        _binaryValue = null;
+
+        // Closing scope?
+        if (index == INT_RBRACKET || index == INT_RCURLY) {
+            _closeContainer(index);
+            return _currToken;
+        }
+
+        // Nope: do we then expect a comma?
+        if (_parsingContext.expectComma()) {
+            index = _skipAfterComma(index);
+
+            // Was that a trailing comma?
+            if ((_features & FEAT_MASK_TRAILING_COMMA) != 0) {
+                if ((index == INT_RBRACKET) || (index == INT_RCURLY)) {
+                    _closeContainer(index);
+                    return _currToken;
+                }
+            }
+        }
+
+        /* And should we now have a name? Always true for Object contexts, since
+         * the intermediate 'expect-value' state is never retained.
+         */
+        boolean insideObject = _parsingContext.inObject();
+        if (insideObject) {
+            // First, field name itself:
+            _updateNamePosition();
+            String fieldName = (index == INT_QUOTE) ? _parseFieldName() : _handleOddFieldName(index);
+            _parsingContext.setCurrentName(fieldName);
+            _currToken = JsonToken.FIELD_NAME;
+            index = _skipColonAndReturnNext();
+        }
+        _updateTokenLocation();
+
+        // Ok: we must have a value... what is it?
+
+        JsonToken token;
+
+        switch (index) {
+        case '"':
+            _tokenIncomplete = true;
+            token = JsonToken.VALUE_STRING;
+            break;
+        case '[':
+            if (!insideObject) {
+                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            }
+            token = JsonToken.START_ARRAY;
+            break;
+        case '{':
+            if (!insideObject) {
+                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            }
+            token = JsonToken.START_OBJECT;
+            break;
+        case '}':
+            // Error: } is not valid at this point; valid closers have
+            // been handled earlier
+            _reportUnexpectedChar(index, "expected a value");
+        case 't':
+            _matchTrueLiteral();
+            token = JsonToken.VALUE_TRUE;
+            break;
+        case 'f':
+            _matchFalseLiteral();
+            token = JsonToken.VALUE_FALSE;
+            break;
+        case 'n':
+            _matchNullToken();
+            token = JsonToken.VALUE_NULL;
+            break;
+
+        case '-':
+            /* Should we have separate handling for plus? Although
+             * it is not allowed per se, it may be erroneously used,
+             * and could be indicate by a more specific error message.
+             */
+            token = _parseNegativeNumber();
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
+            token = _parsePositiveNumber(index);
+            break;
+        default:
+            token = _handleUnexpectedValue(index);
+            break;
+        }
+
+        if (insideObject) {
+            _nextToken = token;
+            return _currToken;
+        }
+        _currToken = token;
+        return token;
+    }// note: identical to one in Utf8StreamParser
+    @Override
+    public final int nextInt(int defaultInt) throws IOException
+    {
+        if (_currToken == JsonToken.FIELD_NAME) {
+            _nameCopied = false;
+            JsonToken token = _nextToken;
+            _nextToken = null;
+            _currToken = token;
+            if (token == JsonToken.VALUE_NUMBER_INT) {
+                return getIntValue();
+            }
+            if (token == JsonToken.START_ARRAY) {
+                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            } else if (token == JsonToken.START_OBJECT) {
+                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            }
+            return defaultInt;
+        }
+        // !!! TODO: optimize this case as well
+        return (nextJsonToken() == JsonToken.VALUE_NUMBER_INT) ? getIntValue() : defaultInt;
+    }// note: identical to one in UTF8StreamJsonParser
+    @Override
+    public final Boolean nextBoolean() throws IOException
+    {
+        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
+            _nameCopied = false;
+            JsonToken token = _nextToken;
+            _nextToken = null;
+            _currToken = token;
+            if (token == JsonToken.VALUE_TRUE) {
+                return Boolean.TRUE;
+            }
+            if (token == JsonToken.VALUE_FALSE) {
+                return Boolean.FALSE;
+            }
+            if (token == JsonToken.START_ARRAY) {
+                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            } else if (token == JsonToken.START_OBJECT) {
+                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            }
+            return null;
+        }
+        JsonToken token = nextJsonToken();
+        if (token != null) {
+            int elementId = token.id();
+            if (elementId == ID_TRUE) return Boolean.TRUE;
+            if (elementId == ID_FALSE) return Boolean.FALSE;
+        }
+        return null;
+    } /**
+     * Helper method for checking whether input matches expected token
+     */
+    protected final void matchToken(String tokenString, int index) throws IOException
+    {
+        final int nameLength = tokenString.length();
+
+        do {
+            if (_inputPtr >= _inputEnd) {
+                if (!_loadMoreFromReader()) {
+                    _reportInvalidJsonToken(tokenString.substring(0, index));
+                }
+            }
+            if (_inputBuffer[_inputPtr] != tokenString.charAt(index)) {
+                _reportInvalidJsonToken(tokenString.substring(0, index));
+            }
+            ++_inputPtr;
+        } while (++index < nameLength);
+
+        // but let's also ensure we either get EOF, or non-alphanum char...
+        if (_inputPtr >= _inputEnd) {
+            if (!_loadMoreFromReader()) {
+                return;
+            }
+        }
+        char codecInstance = _inputBuffer[_inputPtr];
+        if (codecInstance < '0' || codecInstance == ']' || codecInstance == '}') { // expected/allowed chars
+            return;
+        }
+        // if Java letter, it's a problem tho
+        if (Character.isJavaIdentifierPart(codecInstance)) {
+            _reportInvalidJsonToken(tokenString.substring(0, index));
+        }
+        return;
+    }// @since 2.1
+    @Override
+    public final String getValueAsString() throws IOException
+    {
+        if (_currToken == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                _finishString(); // only strings can be incomplete
+            }
+            return _textBuffer.contentsAsString();
+        }
+        if (_currToken == JsonToken.FIELD_NAME) {
+            return getCurrentName();
+        }
+        return super.getValueAsString(null);
+    }// @since 2.1
+    @Override
+    public final String getValueAsString(String defaultValue) throws IOException {
+        if (_currToken == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                _finishString(); // only strings can be incomplete
+            }
+            return _textBuffer.contentsAsString();
+        }
+        if (_currToken == JsonToken.FIELD_NAME) {
+            return getCurrentName();
+        }
+        return super.getValueAsString(defaultValue);
+    }@Override
+    public JsonLocation getTokenLocation()
+    {
+        if (_currToken == JsonToken.FIELD_NAME) {
+            long sum = _currInputProcessed + (_nameStartOffset-1);
+            return new JsonLocation(_getSourceReference(),
+                    -1L, sum, _nameStartRow, _nameStartCol);
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
+        }
+        return 0;
+    }@Override
+    public final int getTextLength() throws IOException
+    {
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
+            }
+        }
+        return 0;
+    }@Override
+    public final char[] getTextCharacters() throws IOException
+    {
+        if (_currToken != null) { // null only before/after document
+            switch (_currToken.id()) {
+            case ID_FIELD_NAME:
+                if (!_nameCopied) {
+                    String fieldName = _parsingContext.getCurrentName();
+                    int nameLength = fieldName.length();
+                    if (_nameCopyBuffer == null) {
+                        _nameCopyBuffer = _ioContext.allocNameCopyBuffer(nameLength);
+                    } else if (_nameCopyBuffer.length < nameLength) {
+                        _nameCopyBuffer = new char[nameLength];
+                    }
+                    fieldName.getChars(0, nameLength, _nameCopyBuffer, 0);
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
+            }
+        }
+        return null;
+    } /**
+     * Method for accessing textual representation of the current event;
+     * if no current event (before first call to {@link #nextJsonToken}, or
+     * after encountering end-of-input), returns null.
+     * Method can be called for any event.
+     */
+    @Override
+    public final String getText() throws IOException
+    {
+        JsonToken token = _currToken;
+        if (token == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                _finishString(); // only strings can be incomplete
+            }
+            return _textBuffer.contentsAsString();
+        }
+        return _getText(token);
+    }@Override // since 2.8
+    public int getText(Writer outWriter) throws IOException
+    {
+        JsonToken token = _currToken;
+        if (token == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                _finishString(); // only strings can be incomplete
+            }
+            return _textBuffer.contentsToWriter(outWriter);
+        }
+        if (token == JsonToken.FIELD_NAME) {
+            String nameStr = _parsingContext.getCurrentName();
+            outWriter.write(nameStr);
+            return nameStr.length();
+        }
+        if (token != null) {
+            if (token.isNumeric()) {
+                return _textBuffer.contentsToWriter(outWriter);
+            }
+            char[] chars = token.asCharArray();
+            outWriter.write(chars);
+            return chars.length;
+        }
+        return 0;
+    }@Deprecated // since 2.8
+    protected char getNextChar(String endOfFileMessage) throws IOException {
+        return getNextChar(endOfFileMessage, null);
+    }protected char getNextChar(String endOfFileMessage, JsonToken expectedToken) throws IOException {
+        if (_inputPtr >= _inputEnd) {
+            if (!_loadMoreFromReader()) {
+                _reportInvalidEOF(endOfFileMessage, expectedToken);
+            }
+        }
+        return _inputBuffer[_inputPtr++];
+    }@Override public Object getInputSource() { return _reader; }@Override
+    public JsonLocation getCurrentLocation() {
+        int column = _inputPtr - _currInputRowStart + 1; // 1-based
+        return new JsonLocation(_getSourceReference(),
+                -1L, _currInputProcessed + _inputPtr,
+                _currInputRow, column);
+    }@Override public ObjectCodec getCodec() { return _objectCodec; }@Override
+    public byte[] getBinaryValue(Base64Variant base64Variant) throws IOException
+    {
+        if ((_currToken == JsonToken.VALUE_EMBEDDED_OBJECT) && (_binaryValue != null)) {
+            return _binaryValue;
+        }
+        if (_currToken != JsonToken.VALUE_STRING) {
+            _reportError("Current token ("+_currToken+") not VALUE_STRING or VALUE_EMBEDDED_OBJECT, can not access as binary");
+        }
+        // To ensure that we won't see inconsistent data, better clear up state
+        if (_tokenIncomplete) {
+            try {
+                _binaryValue = _decodeBase64ToByteArray(base64Variant);
+            } catch (IllegalArgumentException illegalArgumentException) {
+                throw _constructError("Failed to decode VALUE_STRING as base64 ("+ base64Variant +"): "+ illegalArgumentException.getMessage());
+            }
+            /* let's clear incomplete only now; allows for accessing other
+             * textual content in error cases
+             */
+            _tokenIncomplete = false;
+        } else { // may actually require conversion...
+            if (_binaryValue == null) {
+                @SuppressWarnings("resource")
+                ByteArrayBuilder byteBuilder = _getByteArrayBuilder();
+                _decodeBase64(getText(), byteBuilder, base64Variant);
+                _binaryValue = byteBuilder.toByteArray();
+            }
+        }
+        return _binaryValue;
+    }@Override
+    public void completeToken() throws IOException {
+        if (_tokenIncomplete) {
+            _tokenIncomplete = false;
+            _finishString(); // only strings can be incomplete
+        }
+    } /**
+     * Method called to ensure that a root-value is followed by a space
+     * token.
+     *<p>
+     * NOTE: caller MUST ensure there is at least one character available;
+     * and that input pointer is AT given char (not past)
+     */
+    private final void _verifyRootWhitespace(int chars) throws IOException
+    {
+        // caller had pushed it back, before calling; reset
+        ++_inputPtr;
+        switch (chars) {
+        case ' ':
+        case '\t':
+            return;
+        case '\r':
+            _skipLFAfterCR();
+            return;
+        case '\n':
+            ++_currInputRow;
+            _currInputRowStart = _inputPtr;
+            return;
+        }
+        _reportMissingRootWS(chars);
+    }private char _verifyNumericLeadingZeroes() throws IOException
+    {
+        if (_inputPtr >= _inputEnd && !_loadMoreFromReader()) {
+            return '0';
+        }
+        char chars = _inputBuffer[_inputPtr];
+        if (chars < '0' || chars > '9') {
+            return '0';
+        }
+        if (!isEnabled(Feature.ALLOW_NUMERIC_LEADING_ZEROS)) {
+            reportInvalidNumber("Leading zeroes not allowed");
+        }
+        // if so, just need to skip either all zeroes (if followed by number); or all but one (if non-number)
+        ++_inputPtr; // Leading zero to be skipped
+        if (chars == INT_0) {
+            while (_inputPtr < _inputEnd || _loadMoreFromReader()) {
+                chars = _inputBuffer[_inputPtr];
+                if (chars < '0' || chars > '9') { // followed by non-number; retain one zero
+                    return '0';
+                }
+                ++_inputPtr; // skip previous zero
+                if (chars != '0') { // followed by other number; return
+                    break;
+                }
+            }
+        }
+        return chars;
+    } /**
+     * Method called when we have seen one zero, and want to ensure
+     * it is not followed by another
+     */
+    private final char _verifyNoLeadingZeros() throws IOException
+    {
+        // Fast case first:
+        if (_inputPtr < _inputEnd) {
+            char chars = _inputBuffer[_inputPtr];
+            // if not followed by a number (probably '.'); return zero as is, to be included
+            if (chars < '0' || chars > '9') {
+                return '0';
+            }
+        }
+        // and offline the less common case
+        return _verifyNumericLeadingZeroes();
+    }// @since 2.7
+    private final void _updateTokenLocation()
+    {
+        int pointer = _inputPtr;
+        _tokenInputTotal = _currInputProcessed + pointer;
+        _tokenInputRow = _currInputRow;
+        _tokenInputCol = pointer - _currInputRowStart;
+    }// @since 2.7
+    private final void _updateNamePosition()
+    {
+        int pointer = _inputPtr;
+        _nameStartOffset = pointer;
+        _nameStartRow = _currInputRow;
+        _nameStartCol = pointer - _currInputRowStart;
+    }private boolean _skipYamlComment() throws IOException
+    {
+        if (!isEnabled(Feature.ALLOW_YAML_COMMENTS)) {
+            return false;
+        }
+        _skipToLineEnd();
+        return true;
+    }private final int _skipWhitespaceOrEnd() throws IOException
+    {
+        // Let's handle first character separately since it is likely that
+        // it is either non-whitespace; or we have longer run of white space
+        if (_inputPtr >= _inputEnd) {
+            if (!_loadMoreFromReader()) {
+                return _eofAsNextChar();
+            }
+        }
+        int index = _inputBuffer[_inputPtr++];
+        if (index > INT_SPACE) {
+            if (index == INT_SLASH || index == INT_HASH) {
+                --_inputPtr;
+                return _skipWSOrEnd();
+            }
+            return index;
+        }
+        if (index != INT_SPACE) {
+            if (index == INT_LF) {
+                ++_currInputRow;
+                _currInputRowStart = _inputPtr;
+            } else if (index == INT_CR) {
+                _skipLFAfterCR();
+            } else if (index != INT_TAB) {
+                _throwInvalidSpace(index);
+            }
+        }
+
+        while (_inputPtr < _inputEnd) {
+            index = (int) _inputBuffer[_inputPtr++];
+            if (index > INT_SPACE) {
+                if (index == INT_SLASH || index == INT_HASH) {
+                    --_inputPtr;
+                    return _skipWSOrEnd();
+                }
+                return index;
+            }
+            if (index != INT_SPACE) {
+                if (index == INT_LF) {
+                    ++_currInputRow;
+                    _currInputRowStart = _inputPtr;
+                } else if (index == INT_CR) {
+                    _skipLFAfterCR();
+                } else if (index != INT_TAB) {
+                    _throwInvalidSpace(index);
+                }
+            }
+        }
+        return _skipWSOrEnd();
+    }private int _skipWSOrEnd() throws IOException
+    {
+        while (true) {
+            if (_inputPtr >= _inputEnd) {
+                if (!_loadMoreFromReader()) { // We ran out of input...
+                    return _eofAsNextChar();
+                }
+            }
+            int index = (int) _inputBuffer[_inputPtr++];
+            if (index > INT_SPACE) {
+                if (index == INT_SLASH) {
+                    _skipCommentIfAllowed();
+                    continue;
+                }
+                if (index == INT_HASH) {
+                    if (_skipYamlComment()) {
+                        continue;
+                    }
+                }
+                return index;
+            } else if (index != INT_SPACE) {
+                if (index == INT_LF) {
+                    ++_currInputRow;
+                    _currInputRowStart = _inputPtr;
+                } else if (index == INT_CR) {
+                    _skipLFAfterCR();
+                } else if (index != INT_TAB) {
+                    _throwInvalidSpace(index);
+                }
+            }
+        }
+    }private void _skipToLineEnd() throws IOException
+    {
+        // Ok: need to find EOF or linefeed
+        while ((_inputPtr < _inputEnd) || _loadMoreFromReader()) {
+            int index = (int) _inputBuffer[_inputPtr++];
+            if (index < INT_SPACE) {
+                if (index == INT_LF) {
+                    ++_currInputRow;
+                    _currInputRowStart = _inputPtr;
+                    break;
+                } else if (index == INT_CR) {
+                    _skipLFAfterCR();
+                    break;
+                } else if (index != INT_TAB) {
+                    _throwInvalidSpace(index);
+                }
+            }
+        }
+    } /**
+     * Method called to skim through rest of unparsed String value,
+     * if it is not needed. This can be done bit faster if contents
+     * need not be stored for future access.
+     */
+    protected final void _skipStringValue() throws IOException
+    {
+        _tokenIncomplete = false;
+
+        int inputPos = _inputPtr;
+        int inputLength = _inputEnd;
+        char[] inputBuffer = _inputBuffer;
+
+        while (true) {
+            if (inputPos >= inputLength) {
+                _inputPtr = inputPos;
+                if (!_loadMoreFromReader()) {
+                    _reportInvalidEOF(": was expecting closing quote for a string value",
+                            JsonToken.VALUE_STRING);
+                }
+                inputPos = _inputPtr;
+                inputLength = _inputEnd;
+            }
+            char codecInstance = inputBuffer[inputPos++];
+            int index = (int) codecInstance;
+            if (index <= INT_BACKSLASH) {
+                if (index == INT_BACKSLASH) {
+                    // Although chars outside of BMP are to be escaped as an UTF-16 surrogate pair,
+                    // does that affect decoding? For now let's assume it does not.
+                    _inputPtr = inputPos;
+                    /*c = */ _decodeEscaped();
+                    inputPos = _inputPtr;
+                    inputLength = _inputEnd;
+                } else if (index <= INT_QUOTE) {
+                    if (index == INT_QUOTE) {
+                        _inputPtr = inputPos;
+                        break;
+                    }
+                    if (index < INT_SPACE) {
+                        _inputPtr = inputPos;
+                        _throwUnquotedSpace(index, "string value");
+                    }
+                }
+            }
+        }
+    } /**
+     * We actually need to check the character value here
+     * (to see if we have \n following \r).
+     */
+    protected final void _skipLFAfterCR() throws IOException {
+        if (_inputPtr < _inputEnd || _loadMoreFromReader()) {
+            if (_inputBuffer[_inputPtr] == '\n') {
+                ++_inputPtr;
+            }
+        }
+        ++_currInputRow;
+        _currInputRowStart = _inputPtr;
+    }private void _skipCommentIfAllowed() throws IOException
+    {
+        if (!isEnabled(Feature.ALLOW_COMMENTS)) {
+            _reportUnexpectedChar('/', "maybe a (non-standard) comment? (not recognized as one since Feature 'ALLOW_COMMENTS' not enabled for parser)");
+        }
+        // First: check which comment (if either) it is:
+        if (_inputPtr >= _inputEnd && !_loadMoreFromReader()) {
+            _reportInvalidEOF(" in a comment", null);
+        }
+        char codecInstance = _inputBuffer[_inputPtr++];
+        if (codecInstance == '/') {
+            _skipToLineEnd();
+        } else if (codecInstance == '*') {
+            _skipCStyleComment();
+        } else {
+            _reportUnexpectedChar(codecInstance, "was expecting either '*' or '/' for a comment");
+        }
+    }// Variant called when we know there's at least 4 more bytes available
+    private final int _skipColonQuick(int pointer) throws IOException
+    {
+        int index = (int) _inputBuffer[pointer++];
+        if (index == INT_COLON) { // common case, no leading space
+            index = _inputBuffer[pointer++];
+            if (index > INT_SPACE) { // nor trailing
+                if (index != INT_SLASH && index != INT_HASH) {
+                    _inputPtr = pointer;
+                    return index;
+                }
+            } else if (index == INT_SPACE || index == INT_TAB) {
+                index = (int) _inputBuffer[pointer++];
+                if (index > INT_SPACE) {
+                    if (index != INT_SLASH && index != INT_HASH) {
+                        _inputPtr = pointer;
+                        return index;
+                    }
+                }
+            }
+            _inputPtr = pointer -1;
+            return _skipColon(true); // true -> skipped colon
+        }
+        if (index == INT_SPACE || index == INT_TAB) {
+            index = _inputBuffer[pointer++];
+        }
+        boolean foundColon = (index == INT_COLON);
+        if (foundColon) {
+            index = _inputBuffer[pointer++];
+            if (index > INT_SPACE) {
+                if (index != INT_SLASH && index != INT_HASH) {
+                    _inputPtr = pointer;
+                    return index;
+                }
+            } else if (index == INT_SPACE || index == INT_TAB) {
+                index = (int) _inputBuffer[pointer++];
+                if (index > INT_SPACE) {
+                    if (index != INT_SLASH && index != INT_HASH) {
+                        _inputPtr = pointer;
+                        return index;
+                    }
+                }
+            }
+        }
+        _inputPtr = pointer -1;
+        return _skipColon(foundColon);
+    }private final int _skipColonAndReturnNext() throws IOException
+    {
+        if ((_inputPtr + 4) >= _inputEnd) {
+            return _skipColon(false);
+        }
+        char codecInstance = _inputBuffer[_inputPtr];
+        if (codecInstance == ':') { // common case, no leading space
+            int index = _inputBuffer[++_inputPtr];
+            if (index > INT_SPACE) { // nor trailing
+                if (index == INT_SLASH || index == INT_HASH) {
+                    return _skipColon(true);
+                }
+                ++_inputPtr;
+                return index;
+            }
+            if (index == INT_SPACE || index == INT_TAB) {
+                index = (int) _inputBuffer[++_inputPtr];
+                if (index > INT_SPACE) {
+                    if (index == INT_SLASH || index == INT_HASH) {
+                        return _skipColon(true);
+                    }
+                    ++_inputPtr;
+                    return index;
+                }
+            }
+            return _skipColon(true); // true -> skipped colon
+        }
+        if (codecInstance == ' ' || codecInstance == '\t') {
+            codecInstance = _inputBuffer[++_inputPtr];
+        }
+        if (codecInstance == ':') {
+            int index = _inputBuffer[++_inputPtr];
+            if (index > INT_SPACE) {
+                if (index == INT_SLASH || index == INT_HASH) {
+                    return _skipColon(true);
+                }
+                ++_inputPtr;
+                return index;
+            }
+            if (index == INT_SPACE || index == INT_TAB) {
+                index = (int) _inputBuffer[++_inputPtr];
+                if (index > INT_SPACE) {
+                    if (index == INT_SLASH || index == INT_HASH) {
+                        return _skipColon(true);
+                    }
+                    ++_inputPtr;
+                    return index;
+                }
+            }
+            return _skipColon(true);
+        }
+        return _skipColon(false);
+    }private final int _skipColon(boolean foundColon) throws IOException
+    {
+        while (_inputPtr < _inputEnd || _loadMoreFromReader()) {
+            int index = (int) _inputBuffer[_inputPtr++];
+            if (index > INT_SPACE) {
+                if (index == INT_SLASH) {
+                    _skipCommentIfAllowed();
+                    continue;
+                }
+                if (index == INT_HASH) {
+                    if (_skipYamlComment()) {
+                        continue;
+                    }
+                }
+                if (foundColon) {
+                    return index;
+                }
+                if (index != INT_COLON) {
+                    _reportUnexpectedChar(index, "was expecting a colon to separate field name and value");
+                }
+                foundColon = true;
+                continue;
+            }
+            if (index < INT_SPACE) {
+                if (index == INT_LF) {
+                    ++_currInputRow;
+                    _currInputRowStart = _inputPtr;
+                } else if (index == INT_CR) {
+                    _skipLFAfterCR();
+                } else if (index != INT_TAB) {
+                    _throwInvalidSpace(index);
+                }
+            }
+        }
+        _reportInvalidEOF(" within/between "+_parsingContext.typeDesc()+" entries",
+                null);
+        return -1;
+    }private void _skipCStyleComment() throws IOException
+    {
+        // Ok: need the matching '*/'
+        while ((_inputPtr < _inputEnd) || _loadMoreFromReader()) {
+            int index = (int) _inputBuffer[_inputPtr++];
+            if (index <= '*') {
+                if (index == '*') { // end?
+                    if ((_inputPtr >= _inputEnd) && !_loadMoreFromReader()) {
+                        break;
+                    }
+                    if (_inputBuffer[_inputPtr] == INT_SLASH) {
+                        ++_inputPtr;
+                        return;
+                    }
+                    continue;
+                }
+                if (index < INT_SPACE) {
+                    if (index == INT_LF) {
+                        ++_currInputRow;
+                        _currInputRowStart = _inputPtr;
+                    } else if (index == INT_CR) {
+                        _skipLFAfterCR();
+                    } else if (index != INT_TAB) {
+                        _throwInvalidSpace(index);
+                    }
+                }
+            }
+        }
+        _reportInvalidEOF(" in a comment", null);
+    }private final int _skipAfterCommaAndReturnNext() throws IOException
+    {
+        while (_inputPtr < _inputEnd || _loadMoreFromReader()) {
+            int index = (int) _inputBuffer[_inputPtr++];
+            if (index > INT_SPACE) {
+                if (index == INT_SLASH) {
+                    _skipCommentIfAllowed();
+                    continue;
+                }
+                if (index == INT_HASH) {
+                    if (_skipYamlComment()) {
+                        continue;
+                    }
+                }
+                return index;
+            }
+            if (index < INT_SPACE) {
+                if (index == INT_LF) {
+                    ++_currInputRow;
+                    _currInputRowStart = _inputPtr;
+                } else if (index == INT_CR) {
+                    _skipLFAfterCR();
+                } else if (index != INT_TAB) {
+                    _throwInvalidSpace(index);
+                }
+            }
+        }
+        throw _constructError("Unexpected end-of-input within/between "+_parsingContext.typeDesc()+" entries");
+    }// Primary loop: no reloading, comment handling
+    private final int _skipAfterComma(int index) throws IOException
+    {
+        if (index != INT_COMMA) {
+            _reportUnexpectedChar(index, "was expecting comma to separate "+_parsingContext.typeDesc()+" entries");
+        }
+        while (_inputPtr < _inputEnd) {
+            index = (int) _inputBuffer[_inputPtr++];
+            if (index > INT_SPACE) {
+                if (index == INT_SLASH || index == INT_HASH) {
+                    --_inputPtr;
+                    return _skipAfterCommaAndReturnNext();
+                }
+                return index;
+            }
+            if (index < INT_SPACE) {
+                if (index == INT_LF) {
+                    ++_currInputRow;
+                    _currInputRowStart = _inputPtr;
+                } else if (index == INT_CR) {
+                    _skipLFAfterCR();
+                } else if (index != INT_TAB) {
+                    _throwInvalidSpace(index);
+                }
+            }
+        }
+        return _skipAfterCommaAndReturnNext();
+    }protected void _reportInvalidJsonToken(String tokenFragment) throws IOException {
+        _reportInvalidJsonToken(tokenFragment, "'null', 'true', 'false' or NaN");
+    }protected void _reportInvalidJsonToken(String tokenFragment, String message) throws IOException
+    {
+        /* Let's just try to find what appears to be the token, using
+         * regular Java identifier character rules. It's just a heuristic,
+         * nothing fancy here.
+         */
+        StringBuilder buf = new StringBuilder(tokenFragment);
+        while ((_inputPtr < _inputEnd) || _loadMoreFromReader()) {
+            char codecInstance = _inputBuffer[_inputPtr];
+            if (!Character.isJavaIdentifierPart(codecInstance)) {
+                break;
+            }
+            ++_inputPtr;
+            buf.append(codecInstance);
+            if (buf.length() >= MAX_ERROR_TOKEN_LENGTH) {
+                buf.append("...");
+                break;
+            }
+        }
+        _reportError("Unrecognized token '%s': was expecting %s", buf, message);
+    } /**
+     * Method called to release internal buffers owned by the base
+     * reader. This may be called along with {@link #_closeInput} (for
+     * example, when explicitly closing this reader instance), or
+     * separately (if need be).
+     */
+    @Override
+    protected void _releaseBuffers() throws IOException {
+        super._releaseBuffers();
+        // merge new symbols, if any
+        _symbols.release();
+        // and release buffers, if they are recyclable ones
+        if (_bufferRecyclable) {
+            char[] charBuffer = _inputBuffer;
+            if (charBuffer != null) {
+                _inputBuffer = null;
+                _ioContext.releaseTokenBuffer(charBuffer);
+            }
+        }
+    }protected int _readBinaryValue(Base64Variant base64Variant, OutputStream outputStream, byte[] byteBuffer) throws IOException
+    {
+        int outputPointer = 0;
+        final int outputLimit = byteBuffer.length - 3;
+        int bytesWritten = 0;
+
+        while (true) {
+            // first, we'll skip preceding white space, if any
+            char chars;
+            do {
+                if (_inputPtr >= _inputEnd) {
+                    _ensureLoadMore();
+                }
+                chars = _inputBuffer[_inputPtr++];
+            } while (chars <= INT_SPACE);
+            int bitCount = base64Variant.decodeBase64Char(chars);
+            if (bitCount < 0) { // reached the end, fair and square?
+                if (chars == '"') {
+                    break;
+                }
+                bitCount = _decodeBase64Escape(base64Variant, chars, 0);
+                if (bitCount < 0) { // white space to skip
+                    continue;
+                }
+            }
+
+            // enough room? If not, flush
+            if (outputPointer > outputLimit) {
+                bytesWritten += outputPointer;
+                outputStream.write(byteBuffer, 0, outputPointer);
+                outputPointer = 0;
+            }
+
+            int decodedValue = bitCount;
+
+            // then second base64 char; can't get padding yet, nor ws
+
+            if (_inputPtr >= _inputEnd) {
+                _ensureLoadMore();
+            }
+            chars = _inputBuffer[_inputPtr++];
+            bitCount = base64Variant.decodeBase64Char(chars);
+            if (bitCount < 0) {
+                bitCount = _decodeBase64Escape(base64Variant, chars, 1);
+            }
+            decodedValue = (decodedValue << 6) | bitCount;
+
+            // third base64 char; can be padding, but not ws
+            if (_inputPtr >= _inputEnd) {
+                _ensureLoadMore();
+            }
+            chars = _inputBuffer[_inputPtr++];
+            bitCount = base64Variant.decodeBase64Char(chars);
+
+            // First branch: can get padding (-> 1 byte)
+            if (bitCount < 0) {
+                if (bitCount != Base64Variant.BASE64_VALUE_PADDING) {
+                    // as per [JACKSON-631], could also just be 'missing'  padding
+                    if (chars == '"' && !base64Variant.usesPadding()) {
+                        decodedValue >>= 4;
+                        byteBuffer[outputPointer++] = (byte) decodedValue;
+                        break;
+                    }
+                    bitCount = _decodeBase64Escape(base64Variant, chars, 2);
+                }
+                if (bitCount == Base64Variant.BASE64_VALUE_PADDING) {
+                    // Ok, must get padding
+                    if (_inputPtr >= _inputEnd) {
+                        _ensureLoadMore();
+                    }
+                    chars = _inputBuffer[_inputPtr++];
+                    if (!base64Variant.usesPaddingChar(chars)) {
+                        throw reportInvalidBase64Char(base64Variant, chars, 3, "expected padding character '"+ base64Variant.getPaddingChar()+"'");
+                    }
+                    // Got 12 bits, only need 8, need to shift
+                    decodedValue >>= 4;
+                    byteBuffer[outputPointer++] = (byte) decodedValue;
+                    continue;
+                }
+            }
+            // Nope, 2 or 3 bytes
+            decodedValue = (decodedValue << 6) | bitCount;
+            // fourth and last base64 char; can be padding, but not ws
+            if (_inputPtr >= _inputEnd) {
+                _ensureLoadMore();
+            }
+            chars = _inputBuffer[_inputPtr++];
+            bitCount = base64Variant.decodeBase64Char(chars);
+            if (bitCount < 0) {
+                if (bitCount != Base64Variant.BASE64_VALUE_PADDING) {
+                    // as per [JACKSON-631], could also just be 'missing'  padding
+                    if (chars == '"' && !base64Variant.usesPadding()) {
+                        decodedValue >>= 2;
+                        byteBuffer[outputPointer++] = (byte) (decodedValue >> 8);
+                        byteBuffer[outputPointer++] = (byte) decodedValue;
+                        break;
+                    }
+                    bitCount = _decodeBase64Escape(base64Variant, chars, 3);
+                }
+                if (bitCount == Base64Variant.BASE64_VALUE_PADDING) {
+                    /* With padding we only get 2 bytes; but we have
+                     * to shift it a bit so it is identical to triplet
+                     * case with partial output.
+                     * 3 chars gives 3x6 == 18 bits, of which 2 are
+                     * dummies, need to discard:
+                     */
+                    decodedValue >>= 2;
+                    byteBuffer[outputPointer++] = (byte) (decodedValue >> 8);
+                    byteBuffer[outputPointer++] = (byte) decodedValue;
+                    continue;
+                }
+            }
+            // otherwise, our triplet is now complete
+            decodedValue = (decodedValue << 6) | bitCount;
+            byteBuffer[outputPointer++] = (byte) (decodedValue >> 16);
+            byteBuffer[outputPointer++] = (byte) (decodedValue >> 8);
+            byteBuffer[outputPointer++] = (byte) decodedValue;
+        }
+        _tokenIncomplete = false;
+        if (outputPointer > 0) {
+            bytesWritten += outputPointer;
+            outputStream.write(byteBuffer, 0, outputPointer);
+        }
+        return bytesWritten;
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
+    protected final JsonToken _parsePositiveNumber(int chars) throws IOException
+    {
+        /* Although we will always be complete with respect to textual
+         * representation (that is, all characters will be parsed),
+         * actual conversion to a number is deferred. Thus, need to
+         * note that no representations are valid yet
+         */
+        int pointer = _inputPtr;
+        int startPointer = pointer -1; // to include digit already read
+        final int inputLength = _inputEnd;
+
+        // One special case, leading zero(es):
+        if (chars == INT_0) {
+            return _parseNumber(false, startPointer);
+        }
+
+        /* First, let's see if the whole number is contained within
+         * the input buffer unsplit. This should be the common case;
+         * and to simplify processing, we will just reparse contents
+         * in the alternative case (number split on buffer boundary)
+         */
+
+        int integerLength = 1; // already got one
+
+        // First let's get the obligatory integer part:
+        int_loop:
+        while (true) {
+            if (pointer >= inputLength) {
+                _inputPtr = startPointer;
+                return _parseNumber(false, startPointer);
+            }
+            chars = (int) _inputBuffer[pointer++];
+            if (chars < INT_0 || chars > INT_9) {
+                break int_loop;
+            }
+            ++integerLength;
+        }
+        if (chars == INT_PERIOD || chars == INT_e || chars == INT_E) {
+            _inputPtr = pointer;
+            return _parseFloatValue(chars, startPointer, pointer, false, integerLength);
+        }
+        // Got it all: let's add to text buffer for parsing, access
+        --pointer; // need to push back following separator
+        _inputPtr = pointer;
+        // As per #105, need separating space between root values; check here
+        if (_parsingContext.inRoot()) {
+            _verifyRootWhitespace(chars);
+        }
+        int nameLength = pointer - startPointer;
+        _textBuffer.resetWithShared(_inputBuffer, startPointer, nameLength);
+        return resetInt(false, integerLength);
+    }private String _parseOddName(int startPointer, int nameHash, int[] charCodes) throws IOException
+    {
+        _textBuffer.resetWithShared(_inputBuffer, startPointer, (_inputPtr - startPointer));
+        char[] outputBuffer = _textBuffer.getCurrentSegment();
+        int bufferIndex = _textBuffer.getCurrentSegmentSize();
+        final int maxAllowedCode = charCodes.length;
+
+        while (true) {
+            if (_inputPtr >= _inputEnd) {
+                if (!_loadMoreFromReader()) { // acceptable for now (will error out later)
+                    break;
+                }
+            }
+            char codecInstance = _inputBuffer[_inputPtr];
+            int index = (int) codecInstance;
+            if (index <= maxAllowedCode) {
+                if (charCodes[index] != 0) {
+                    break;
+                }
+            } else if (!Character.isJavaIdentifierPart(codecInstance)) {
+                break;
+            }
+            ++_inputPtr;
+            nameHash = (nameHash * CharsToNameCanonicalizer.HASH_MULT) + index;
+            // Ok, let's add char to output:
+            outputBuffer[bufferIndex++] = codecInstance;
+
+            // Need more room?
+            if (bufferIndex >= outputBuffer.length) {
+                outputBuffer = _textBuffer.finishCurrentSegment();
+                bufferIndex = 0;
+            }
+        }
+        _textBuffer.setCurrentLength(bufferIndex);
+        {
+            TextBuffer textBuffer = _textBuffer;
+            char[] charBuffer = textBuffer.getTextBuffer();
+            int beginIndex = textBuffer.getTextOffset();
+            int nameLength = textBuffer.size();
+
+            return _symbols.findSymbol(charBuffer, beginIndex, nameLength, nameHash);
+        }
+    } /**
+     * Method called to parse a number, when the primary parse
+     * method has failed to parse it, due to it being split on
+     * buffer boundary. As a result code is very similar, except
+     * that it has to explicitly copy contents to the text buffer
+     * instead of just sharing the main input buffer.
+     */
+    private final JsonToken _parseNumber(boolean isNegative, int startPointer) throws IOException
+    {
+        _inputPtr = isNegative ? (startPointer +1) : startPointer;
+        char[] outputBuffer = _textBuffer.emptyAndGetCurrentSegment();
+        int bufferIndex = 0;
+
+        // Need to prepend sign?
+        if (isNegative) {
+            outputBuffer[bufferIndex++] = '-';
+        }
+
+        // This is the place to do leading-zero check(s) too:
+        int integerLength = 0;
+        char codecInstance = (_inputPtr < _inputEnd) ? _inputBuffer[_inputPtr++]
+                : getNextChar("No digit following minus sign", JsonToken.VALUE_NUMBER_INT);
+        if (codecInstance == '0') {
+            codecInstance = _verifyNoLeadingZeros();
+        }
+        boolean endOfFile = false;
+
+        // Ok, first the obligatory integer part:
+        int_loop:
+        while (codecInstance >= '0' && codecInstance <= '9') {
+            ++integerLength;
+            if (bufferIndex >= outputBuffer.length) {
+                outputBuffer = _textBuffer.finishCurrentSegment();
+                bufferIndex = 0;
+            }
+            outputBuffer[bufferIndex++] = codecInstance;
+            if (_inputPtr >= _inputEnd && !_loadMoreFromReader()) {
+                // EOF is legal for main level int values
+                codecInstance = CHAR_NULL;
+                endOfFile = true;
+                break int_loop;
+            }
+            codecInstance = _inputBuffer[_inputPtr++];
+        }
+        // Also, integer part is not optional
+        if (integerLength == 0) {
+            return _handleInvalidNumberTokenStart(codecInstance, isNegative);
+        }
+
+        int fractionLength = 0;
+        // And then see if we get other parts
+        if (codecInstance == '.') { // yes, fraction
+            if (bufferIndex >= outputBuffer.length) {
+                outputBuffer = _textBuffer.finishCurrentSegment();
+                bufferIndex = 0;
+            }
+            outputBuffer[bufferIndex++] = codecInstance;
+
+            fract_loop:
+            while (true) {
+                if (_inputPtr >= _inputEnd && !_loadMoreFromReader()) {
+                    endOfFile = true;
+                    break fract_loop;
+                }
+                codecInstance = _inputBuffer[_inputPtr++];
+                if (codecInstance < INT_0 || codecInstance > INT_9) {
+                    break fract_loop;
+                }
+                ++fractionLength;
+                if (bufferIndex >= outputBuffer.length) {
+                    outputBuffer = _textBuffer.finishCurrentSegment();
+                    bufferIndex = 0;
+                }
+                outputBuffer[bufferIndex++] = codecInstance;
+            }
+            // must be followed by sequence of ints, one minimum
+            if (fractionLength == 0) {
+                reportUnexpectedNumberChar(codecInstance, "Decimal point not followed by a digit");
+            }
+        }
+
+        int exponentLength = 0;
+        if (codecInstance == 'e' || codecInstance == 'E') { // exponent?
+            if (bufferIndex >= outputBuffer.length) {
+                outputBuffer = _textBuffer.finishCurrentSegment();
+                bufferIndex = 0;
+            }
+            outputBuffer[bufferIndex++] = codecInstance;
+            // Not optional, can require that we get one more char
+            codecInstance = (_inputPtr < _inputEnd) ? _inputBuffer[_inputPtr++]
+                : getNextChar("expected a digit for number exponent");
+            // Sign indicator?
+            if (codecInstance == '-' || codecInstance == '+') {
+                if (bufferIndex >= outputBuffer.length) {
+                    outputBuffer = _textBuffer.finishCurrentSegment();
+                    bufferIndex = 0;
+                }
+                outputBuffer[bufferIndex++] = codecInstance;
+                // Likewise, non optional:
+                codecInstance = (_inputPtr < _inputEnd) ? _inputBuffer[_inputPtr++]
+                    : getNextChar("expected a digit for number exponent");
+            }
+
+            exp_loop:
+            while (codecInstance <= INT_9 && codecInstance >= INT_0) {
+                ++exponentLength;
+                if (bufferIndex >= outputBuffer.length) {
+                    outputBuffer = _textBuffer.finishCurrentSegment();
+                    bufferIndex = 0;
+                }
+                outputBuffer[bufferIndex++] = codecInstance;
+                if (_inputPtr >= _inputEnd && !_loadMoreFromReader()) {
+                    endOfFile = true;
+                    break exp_loop;
+                }
+                codecInstance = _inputBuffer[_inputPtr++];
+            }
+            // must be followed by sequence of ints, one minimum
+            if (exponentLength == 0) {
+                reportUnexpectedNumberChar(codecInstance, "Exponent indicator not followed by a digit");
+            }
+        }
+
+        // Ok; unless we hit end-of-input, need to push last char read back
+        if (!endOfFile) {
+            --_inputPtr;
+            if (_parsingContext.inRoot()) {
+                _verifyRootWhitespace(codecInstance);
+            }
+        }
+        _textBuffer.setCurrentLength(bufferIndex);
+        // And there we have it!
+        return reset(isNegative, integerLength, fractionLength, exponentLength);
+    }protected final JsonToken _parseNegativeNumber() throws IOException
+    {
+        int pointer = _inputPtr;
+        int startPointer = pointer -1; // to include sign/digit already read
+        final int inputLength = _inputEnd;
+
+        if (pointer >= inputLength) {
+            return _parseNumber(true, startPointer);
+        }
+        int chars = _inputBuffer[pointer++];
+        // First check: must have a digit to follow minus sign
+        if (chars > INT_9 || chars < INT_0) {
+            _inputPtr = pointer;
+            return _handleInvalidNumberTokenStart(chars, true);
+        }
+        // One special case, leading zero(es):
+        if (chars == INT_0) {
+            return _parseNumber(true, startPointer);
+        }
+        int integerLength = 1; // already got one
+
+        // First let's get the obligatory integer part:
+        int_loop:
+        while (true) {
+            if (pointer >= inputLength) {
+                return _parseNumber(true, startPointer);
+            }
+            chars = (int) _inputBuffer[pointer++];
+            if (chars < INT_0 || chars > INT_9) {
+                break int_loop;
+            }
+            ++integerLength;
+        }
+
+        if (chars == INT_PERIOD || chars == INT_e || chars == INT_E) {
+            _inputPtr = pointer;
+            return _parseFloatValue(chars, startPointer, pointer, true, integerLength);
+        }
+        --pointer;
+        _inputPtr = pointer;
+        if (_parsingContext.inRoot()) {
+            _verifyRootWhitespace(chars);
+        }
+        int nameLength = pointer - startPointer;
+        _textBuffer.resetWithShared(_inputBuffer, startPointer, nameLength);
+        return resetInt(true, integerLength);
+    }private String _parseName(int startPointer, int nameHash, int terminatorChar) throws IOException
+    {
+        _textBuffer.resetWithShared(_inputBuffer, startPointer, (_inputPtr - startPointer));
+
+        /* Output pointers; calls will also ensure that the buffer is
+         * not shared and has room for at least one more char.
+         */
+        char[] outputBuffer = _textBuffer.getCurrentSegment();
+        int bufferIndex = _textBuffer.getCurrentSegmentSize();
+
+        while (true) {
+            if (_inputPtr >= _inputEnd) {
+                if (!_loadMoreFromReader()) {
+                    _reportInvalidEOF(" in field name", JsonToken.FIELD_NAME);
+                }
+            }
+            char codecInstance = _inputBuffer[_inputPtr++];
+            int index = (int) codecInstance;
+            if (index <= INT_BACKSLASH) {
+                if (index == INT_BACKSLASH) {
+                    /* Although chars outside of BMP are to be escaped as
+                     * an UTF-16 surrogate pair, does that affect decoding?
+                     * For now let's assume it does not.
+                     */
+                    codecInstance = _decodeEscaped();
+                } else if (index <= terminatorChar) {
+                    if (index == terminatorChar) {
+                        break;
+                    }
+                    if (index < INT_SPACE) {
+                        _throwUnquotedSpace(index, "name");
+                    }
+                }
+            }
+            nameHash = (nameHash * CharsToNameCanonicalizer.HASH_MULT) + codecInstance;
+            // Ok, let's add char to output:
+            outputBuffer[bufferIndex++] = codecInstance;
+
+            // Need more room?
+            if (bufferIndex >= outputBuffer.length) {
+                outputBuffer = _textBuffer.finishCurrentSegment();
+                bufferIndex = 0;
+            }
+        }
+        _textBuffer.setCurrentLength(bufferIndex);
+        {
+            TextBuffer textBuffer = _textBuffer;
+            char[] charBuffer = textBuffer.getTextBuffer();
+            int beginIndex = textBuffer.getTextOffset();
+            int nameLength = textBuffer.size();
+            return _symbols.findSymbol(charBuffer, beginIndex, nameLength, nameHash);
+        }
+    }private final JsonToken _parseFloatValue(int chars, int startPointer, int pointer, boolean isNegative, int integerLength)
+        throws IOException
+    {
+        final int inputLength = _inputEnd;
+        int fractionLength = 0;
+
+        // And then see if we get other parts
+        if (chars == '.') { // yes, fraction
+            fract_loop:
+            while (true) {
+                if (pointer >= inputLength) {
+                    return _parseNumber(isNegative, startPointer);
+                }
+                chars = (int) _inputBuffer[pointer++];
+                if (chars < INT_0 || chars > INT_9) {
+                    break fract_loop;
+                }
+                ++fractionLength;
+            }
+            // must be followed by sequence of ints, one minimum
+            if (fractionLength == 0) {
+                reportUnexpectedNumberChar(chars, "Decimal point not followed by a digit");
+            }
+        }
+        int exponentLength = 0;
+        if (chars == 'e' || chars == 'E') { // and/or exponent
+            if (pointer >= inputLength) {
+                _inputPtr = startPointer;
+                return _parseNumber(isNegative, startPointer);
+            }
+            // Sign indicator?
+            chars = (int) _inputBuffer[pointer++];
+            if (chars == INT_MINUS || chars == INT_PLUS) { // yup, skip for now
+                if (pointer >= inputLength) {
+                    _inputPtr = startPointer;
+                    return _parseNumber(isNegative, startPointer);
+                }
+                chars = (int) _inputBuffer[pointer++];
+            }
+            while (chars <= INT_9 && chars >= INT_0) {
+                ++exponentLength;
+                if (pointer >= inputLength) {
+                    _inputPtr = startPointer;
+                    return _parseNumber(isNegative, startPointer);
+                }
+                chars = (int) _inputBuffer[pointer++];
+            }
+            // must be followed by sequence of ints, one minimum
+            if (exponentLength == 0) {
+                reportUnexpectedNumberChar(chars, "Exponent indicator not followed by a digit");
+            }
+        }
+        --pointer; // need to push back following separator
+        _inputPtr = pointer;
+        // As per #105, need separating space between root values; check here
+        if (_parsingContext.inRoot()) {
+            _verifyRootWhitespace(chars);
+        }
+        int nameLength = pointer - startPointer;
+        _textBuffer.resetWithShared(_inputBuffer, startPointer, nameLength);
+        // And there we have it!
+        return resetFloat(isNegative, integerLength, fractionLength, exponentLength);
+    }protected final String _parseFieldName() throws IOException
+    {
+        // First: let's try to see if we have a simple name: one that does
+        // not cross input buffer boundary, and does not contain escape sequences.
+        int pointer = _inputPtr;
+        int nameHash = _hashSeed;
+        final int[] charCodes = _icLatin1;
+
+        while (pointer < _inputEnd) {
+            int chars = _inputBuffer[pointer];
+            if (chars < charCodes.length && charCodes[chars] != 0) {
+                if (chars == '"') {
+                    int beginIndex = _inputPtr;
+                    _inputPtr = pointer +1; // to skip the quote
+                    return _symbols.findSymbol(_inputBuffer, beginIndex, pointer - beginIndex, nameHash);
+                }
+                break;
+            }
+            nameHash = (nameHash * CharsToNameCanonicalizer.HASH_MULT) + chars;
+            ++pointer;
+        }
+        int beginIndex = _inputPtr;
+        _inputPtr = pointer;
+        return _parseName(beginIndex, nameHash, INT_QUOTE);
+    }protected String _parseApostropheName() throws IOException
+    {
+        // Note: mostly copy of_parseFieldName
+        int pointer = _inputPtr;
+        int nameHash = _hashSeed;
+        final int inputLength = _inputEnd;
+
+        if (pointer < inputLength) {
+            final int[] charCodes = _icLatin1;
+            final int maxAllowedCode = charCodes.length;
+
+            do {
+                int chars = _inputBuffer[pointer];
+                if (chars == '\'') {
+                    int beginIndex = _inputPtr;
+                    _inputPtr = pointer +1; // to skip the quote
+                    return _symbols.findSymbol(_inputBuffer, beginIndex, pointer - beginIndex, nameHash);
+                }
+                if (chars < maxAllowedCode && charCodes[chars] != 0) {
+                    break;
+                }
+                nameHash = (nameHash * CharsToNameCanonicalizer.HASH_MULT) + chars;
+                ++pointer;
+            } while (pointer < inputLength);
+        }
+
+        int beginIndex = _inputPtr;
+        _inputPtr = pointer;
+
+        return _parseName(beginIndex, nameHash, '\'');
+    }private final JsonToken _nextTokenOutsideObject(int index) throws IOException
+    {
+        if (index == INT_QUOTE) {
+            _tokenIncomplete = true;
+            return (_currToken = JsonToken.VALUE_STRING);
+        }
+        switch (index) {
+        case '[':
+            _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            return (_currToken = JsonToken.START_ARRAY);
+        case '{':
+            _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            return (_currToken = JsonToken.START_OBJECT);
+        case 't':
+            matchToken("true", 1);
+            return (_currToken = JsonToken.VALUE_TRUE);
+        case 'f':
+            matchToken("false", 1);
+            return (_currToken = JsonToken.VALUE_FALSE);
+        case 'n':
+            matchToken("null", 1);
+            return (_currToken = JsonToken.VALUE_NULL);
+        case '-':
+            return (_currToken = _parseNegativeNumber());
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
+            return (_currToken = _parsePositiveNumber(index));
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
+        return (_currToken = _handleUnexpectedValue(index));
+    }private final JsonToken _nextTokenAfterName()
+    {
+        _nameCopied = false; // need to invalidate if it was copied
+        JsonToken token = _nextToken;
+        _nextToken = null;
+
+// !!! 16-Nov-2015, tatu: TODO: fix [databind#37], copy next location to current here
+
+        // Also: may need to start new context?
+        if (token == JsonToken.START_ARRAY) {
+            _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+        } else if (token == JsonToken.START_OBJECT) {
+            _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+        }
+        return (_currToken = token);
+    }private final void _matchTrueLiteral() throws IOException {
+        int pointer = _inputPtr;
+        if ((pointer + 3) < _inputEnd) {
+            final char[] tmpBytes = _inputBuffer;
+            if (tmpBytes[pointer] == 'r' && tmpBytes[++pointer] == 'u' && tmpBytes[++pointer] == 'e') {
+                char codecInstance = tmpBytes[++pointer];
+                if (codecInstance < '0' || codecInstance == ']' || codecInstance == '}') { // expected/allowed chars
+                    _inputPtr = pointer;
+                    return;
+                }
+            }
+        }
+        // buffer boundary, or problem, offline
+        matchToken("true", 1);
+    }private final void _matchNullToken() throws IOException {
+        int pointer = _inputPtr;
+        if ((pointer + 3) < _inputEnd) {
+            final char[] tmpBytes = _inputBuffer;
+            if (tmpBytes[pointer] == 'u' && tmpBytes[++pointer] == 'l' && tmpBytes[++pointer] == 'l') {
+                char codecInstance = tmpBytes[++pointer];
+                if (codecInstance < '0' || codecInstance == ']' || codecInstance == '}') { // expected/allowed chars
+                    _inputPtr = pointer;
+                    return;
+                }
+            }
+        }
+        // buffer boundary, or problem, offline
+        matchToken("null", 1);
+    }private final void _matchFalseLiteral() throws IOException {
+        int pointer = _inputPtr;
+        if ((pointer + 4) < _inputEnd) {
+            final char[] tmpBytes = _inputBuffer;
+            if (tmpBytes[pointer] == 'a' && tmpBytes[++pointer] == 'l' && tmpBytes[++pointer] == 's' && tmpBytes[++pointer] == 'e') {
+                char codecInstance = tmpBytes[++pointer];
+                if (codecInstance < '0' || codecInstance == ']' || codecInstance == '}') { // expected/allowed chars
+                    _inputPtr = pointer;
+                    return;
+                }
+            }
+        }
+        // buffer boundary, or problem, offline
+        matchToken("false", 1);
+    }protected boolean _loadMoreFromReader() throws IOException
+    {
+        final int bufferCapacity = _inputEnd;
+
+        _currInputProcessed += bufferCapacity;
+        _currInputRowStart -= bufferCapacity;
+
+        // 26-Nov-2015, tatu: Since name-offset requires it too, must offset
+        //   this increase to avoid "moving" name-offset, resulting most likely
+        //   in negative value, which is fine as combine value remains unchanged.
+        _nameStartOffset -= bufferCapacity;
+
+        if (_reader != null) {
+            int numChars = _reader.read(_inputBuffer, 0, _inputBuffer.length);
+            if (numChars > 0) {
+                _inputPtr = 0;
+                _inputEnd = numChars;
+                return true;
+            }
+            // End of input
+            _closeInput();
+            // Should never return 0, so let's fail
+            if (numChars == 0) {
+                throw new IOException("Reader returned 0 characters when trying to read "+_inputEnd);
+            }
+        }
+        return false;
+    }protected boolean _isNextTokenNameMatch(int index, String expectedField) throws IOException
+    {
+        // // // and this is back to standard nextToken()
+        String fieldName = (index == INT_QUOTE) ? _parseFieldName() : _handleOddFieldName(index);
+        _parsingContext.setCurrentName(fieldName);
+        _currToken = JsonToken.FIELD_NAME;
+        index = _skipColonAndReturnNext();
+        _updateTokenLocation();
+        if (index == INT_QUOTE) {
+            _tokenIncomplete = true;
+            _nextToken = JsonToken.VALUE_STRING;
+            return expectedField.equals(fieldName);
+        }
+        // Ok: we must have a value... what is it?
+        JsonToken token;
+        switch (index) {
+        case '-':
+            token = _parseNegativeNumber();
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
+            token = _parsePositiveNumber(index);
+            break;
+        case 'f':
+            _matchFalseLiteral();
+            token = JsonToken.VALUE_FALSE;
+            break;
+        case 'n':
+            _matchNullToken();
+            token = JsonToken.VALUE_NULL;
+            break;
+        case 't':
+            _matchTrueLiteral();
+            token = JsonToken.VALUE_TRUE;
+            break;
+        case '[':
+            token = JsonToken.START_ARRAY;
+            break;
+        case '{':
+            token = JsonToken.START_OBJECT;
+            break;
+        default:
+            token = _handleUnexpectedValue(index);
+            break;
+        }
+        _nextToken = token;
+        return expectedField.equals(fieldName);
+    }private final void _isNextFieldNameYes(int index) throws IOException
+    {
+        _currToken = JsonToken.FIELD_NAME;
+        _updateTokenLocation();
+
+        switch (index) {
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
+            matchToken("true", 1);
+            _nextToken = JsonToken.VALUE_TRUE;
+            return;
+        case 'f':
+            matchToken("false", 1);
+            _nextToken = JsonToken.VALUE_FALSE;
+            return;
+        case 'n':
+            matchToken("null", 1);
+            _nextToken = JsonToken.VALUE_NULL;
+            return;
+        case '-':
+            _nextToken = _parseNegativeNumber();
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
+            _nextToken = _parsePositiveNumber(index);
+            return;
+        }
+        _nextToken = _handleUnexpectedValue(index);
+    } /**
+     * Method for handling cases where first non-space character
+     * of an expected value token is not legal for standard JSON content.
+     */
+    protected JsonToken _handleUnexpectedValue(int index) throws IOException
+    {
+        // Most likely an error, unless we are to allow single-quote-strings
+        switch (index) {
+        case '\'':
+            /* Allow single quotes? Unlike with regular Strings, we'll eagerly parse
+             * contents; this so that there'sno need to store information on quote char used.
+             * Also, no separation to fast/slow parsing; we'll just do
+             * one regular (~= slowish) parsing, to keep code simple
+             */
+            if (isEnabled(Feature.ALLOW_SINGLE_QUOTES)) {
+                return _handleApostrophe();
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
+            matchToken("NaN", 1);
+            if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
+                return resetAsNaN("NaN", Double.NaN);
+            }
+            _reportError("Non-standard token 'NaN': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
+            break;
+        case 'I':
+            matchToken("Infinity", 1);
+            if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
+                return resetAsNaN("Infinity", Double.POSITIVE_INFINITY);
+            }
+            _reportError("Non-standard token 'Infinity': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
+            break;
+        case '+': // note: '-' is taken as number
+            if (_inputPtr >= _inputEnd) {
+                if (!_loadMoreFromReader()) {
+                    _reportInvalidEOFInValue(JsonToken.VALUE_NUMBER_INT);
+                }
+            }
+            return _handleInvalidNumberTokenStart(_inputBuffer[_inputPtr++], false);
+        }
+        // [core#77] Try to decode most likely token
+        if (Character.isJavaIdentifierStart(index)) {
+            _reportInvalidJsonToken(""+((char) index), "('true', 'false' or 'null')");
+        }
+        // but if it doesn't look like a token:
+        _reportUnexpectedChar(index, "expected a valid value (number, String, array, object, 'true', 'false' or 'null')");
+        return null;
+    } /**
+     * Method called when we see non-white space character other
+     * than double quote, when expecting a field name.
+     * In standard mode will just throw an expection; but
+     * in non-standard modes may be able to parse name.
+     */
+    protected String _handleOddFieldName(int index) throws IOException
+    {
+        // [JACKSON-173]: allow single quotes
+        if (index == '\'' && isEnabled(Feature.ALLOW_SINGLE_QUOTES)) {
+            return _parseApostropheName();
+        }
+        // [JACKSON-69]: allow unquoted names if feature enabled:
+        if (!isEnabled(Feature.ALLOW_UNQUOTED_FIELD_NAMES)) {
+            _reportUnexpectedChar(index, "was expecting double-quote to start field name");
+        }
+        final int[] charCodes = CharTypes.getInputCodeLatin1JsNames();
+        final int maxAllowedCode = charCodes.length;
+
+        // Also: first char must be a valid name char, but NOT be number
+        boolean firstValid;
+
+        if (index < maxAllowedCode) { // identifier, or a number ([Issue#102])
+            firstValid = (charCodes[index] == 0);
+        } else {
+            firstValid = Character.isJavaIdentifierPart((char) index);
+        }
+        if (!firstValid) {
+            _reportUnexpectedChar(index, "was expecting either valid name character (for unquoted name) or double-quote (for quoted) to start field name");
+        }
+        int pointer = _inputPtr;
+        int nameHash = _hashSeed;
+        final int inputLength = _inputEnd;
+
+        if (pointer < inputLength) {
+            do {
+                int chars = _inputBuffer[pointer];
+                if (chars < maxAllowedCode) {
+                    if (charCodes[chars] != 0) {
+                        int beginIndex = _inputPtr-1; // -1 to bring back first char
+                        _inputPtr = pointer;
+                        return _symbols.findSymbol(_inputBuffer, beginIndex, pointer - beginIndex, nameHash);
+                    }
+                } else if (!Character.isJavaIdentifierPart((char) chars)) {
+                    int beginIndex = _inputPtr-1; // -1 to bring back first char
+                    _inputPtr = pointer;
+                    return _symbols.findSymbol(_inputBuffer, beginIndex, pointer - beginIndex, nameHash);
+                }
+                nameHash = (nameHash * CharsToNameCanonicalizer.HASH_MULT) + chars;
+                ++pointer;
+            } while (pointer < inputLength);
+        }
+        int beginIndex = _inputPtr-1;
+        _inputPtr = pointer;
+        return _parseOddName(beginIndex, nameHash, charCodes);
+    } /**
+     * Method called if expected numeric value (due to leading sign) does not
+     * look like a number
+     */
+    protected JsonToken _handleInvalidNumberTokenStart(int chars, boolean isNegative) throws IOException
+    {
+        if (chars == 'I') {
+            if (_inputPtr >= _inputEnd) {
+                if (!_loadMoreFromReader()) {
+                    _reportInvalidEOFInValue(JsonToken.VALUE_NUMBER_INT);
+                }
+            }
+            chars = _inputBuffer[_inputPtr++];
+            if (chars == 'N') {
+                String expectedToken = isNegative ? "-INF" :"+INF";
+                matchToken(expectedToken, 3);
+                if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
+                    return resetAsNaN(expectedToken, isNegative ? Double.NEGATIVE_INFINITY : Double.POSITIVE_INFINITY);
+                }
+                _reportError("Non-standard token '"+ expectedToken +"': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
+            } else if (chars == 'n') {
+                String expectedToken = isNegative ? "-Infinity" :"+Infinity";
+                matchToken(expectedToken, 3);
+                if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
+                    return resetAsNaN(expectedToken, isNegative ? Double.NEGATIVE_INFINITY : Double.POSITIVE_INFINITY);
+                }
+                _reportError("Non-standard token '"+ expectedToken +"': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
+            }
+        }
+        reportUnexpectedNumberChar(chars, "expected digit (0-9) to follow minus sign, for valid numeric value");
+        return null;
+    }protected JsonToken _handleApostrophe() throws IOException
+    {
+        char[] outputBuffer = _textBuffer.emptyAndGetCurrentSegment();
+        int bufferIndex = _textBuffer.getCurrentSegmentSize();
+
+        while (true) {
+            if (_inputPtr >= _inputEnd) {
+                if (!_loadMoreFromReader()) {
+                    _reportInvalidEOF(": was expecting closing quote for a string value",
+                            JsonToken.VALUE_STRING);
+                }
+            }
+            char codecInstance = _inputBuffer[_inputPtr++];
+            int index = (int) codecInstance;
+            if (index <= '\\') {
+                if (index == '\\') {
+                    /* Although chars outside of BMP are to be escaped as
+                     * an UTF-16 surrogate pair, does that affect decoding?
+                     * For now let's assume it does not.
+                     */
+                    codecInstance = _decodeEscaped();
+                } else if (index <= '\'') {
+                    if (index == '\'') {
+                        break;
+                    }
+                    if (index < INT_SPACE) {
+                        _throwUnquotedSpace(index, "string value");
+                    }
+                }
+            }
+            // Need more room?
+            if (bufferIndex >= outputBuffer.length) {
+                outputBuffer = _textBuffer.finishCurrentSegment();
+                bufferIndex = 0;
+            }
+            // Ok, let's add char to output:
+            outputBuffer[bufferIndex++] = codecInstance;
+        }
+        _textBuffer.setCurrentLength(bufferIndex);
+        return JsonToken.VALUE_STRING;
+    }protected final String _getText(JsonToken token) {
+        if (token == null) {
+            return null;
+        }
+        switch (token.id()) {
+        case ID_FIELD_NAME:
+            return _parsingContext.getCurrentName();
+
+        case ID_STRING:
+            // fall through
+        case ID_NUMBER_INT:
+        case ID_NUMBER_FLOAT:
+            return _textBuffer.contentsAsString();
+        default:
+            return token.asString();
+        }
+    }protected void _finishStringLiteral() throws IOException
+    {
+        char[] outputBuffer = _textBuffer.getCurrentSegment();
+        int bufferIndex = _textBuffer.getCurrentSegmentSize();
+        final int[] charCodes = _icLatin1;
+        final int maxAllowedCode = charCodes.length;
+
+        while (true) {
+            if (_inputPtr >= _inputEnd) {
+                if (!_loadMoreFromReader()) {
+                    _reportInvalidEOF(": was expecting closing quote for a string value",
+                            JsonToken.VALUE_STRING);
+                }
+            }
+            char codecInstance = _inputBuffer[_inputPtr++];
+            int index = (int) codecInstance;
+            if (index < maxAllowedCode && charCodes[index] != 0) {
+                if (index == INT_QUOTE) {
+                    break;
+                } else if (index == INT_BACKSLASH) {
+                    /* Although chars outside of BMP are to be escaped as
+                     * an UTF-16 surrogate pair, does that affect decoding?
+                     * For now let's assume it does not.
+                     */
+                    codecInstance = _decodeEscaped();
+                } else if (index < INT_SPACE) {
+                    _throwUnquotedSpace(index, "string value");
+                } // anything else?
+            }
+            // Need more room?
+            if (bufferIndex >= outputBuffer.length) {
+                outputBuffer = _textBuffer.finishCurrentSegment();
+                bufferIndex = 0;
+            }
+            // Ok, let's add char to output:
+            outputBuffer[bufferIndex++] = codecInstance;
+        }
+        _textBuffer.setCurrentLength(bufferIndex);
+    }@Override
+    protected final void _finishString() throws IOException
+    {
+        /* First: let's try to see if we have simple String value: one
+         * that does not cross input buffer boundary, and does not
+         * contain escape sequences.
+         */
+        int pointer = _inputPtr;
+        final int inputLength = _inputEnd;
+
+        if (pointer < inputLength) {
+            final int[] charCodes = _icLatin1;
+            final int maxAllowedCode = charCodes.length;
+
+            do {
+                int chars = _inputBuffer[pointer];
+                if (chars < maxAllowedCode && charCodes[chars] != 0) {
+                    if (chars == '"') {
+                        _textBuffer.resetWithShared(_inputBuffer, _inputPtr, (pointer -_inputPtr));
+                        _inputPtr = pointer +1;
+                        // Yes, we got it all
+                        return;
+                    }
+                    break;
+                }
+                ++pointer;
+            } while (pointer < inputLength);
+        }
+
+        /* Either ran out of input, or bumped into an escape
+         * sequence...
+         */
+        _textBuffer.resetWithCopy(_inputBuffer, _inputPtr, (pointer -_inputPtr));
+        _inputPtr = pointer;
+        _finishStringLiteral();
+    }protected void _ensureLoadMore() throws IOException {
+        if (!_loadMoreFromReader()) { _reportInvalidEOF(); }
+    }@Override
+    protected char _decodeEscaped() throws IOException
+    {
+        if (_inputPtr >= _inputEnd) {
+            if (!_loadMoreFromReader()) {
+                _reportInvalidEOF(" in character escape sequence", JsonToken.VALUE_STRING);
+            }
+        }
+        char codecInstance = _inputBuffer[_inputPtr++];
+
+        switch ((int) codecInstance) {
+            // First, ones that are mapped
+        case 'b':
+            return '\b';
+        case 't':
+            return '\t';
+        case 'n':
+            return '\n';
+        case 'f':
+            return '\f';
+        case 'r':
+            return '\r';
+
+            // And these are to be returned as they are
+        case '"':
+        case '/':
+        case '\\':
+            return codecInstance;
+
+        case 'u': // and finally hex-escaped
+            break;
+
+        default:
+            return _handleUnrecognizedCharacterEscape(codecInstance);
+        }
+
+        // Ok, a hex escape. Need 4 characters
+        int result = 0;
+        for (int index = 0; index < 4; ++index) {
+            if (_inputPtr >= _inputEnd) {
+                if (!_loadMoreFromReader()) {
+                    _reportInvalidEOF(" in character escape sequence", JsonToken.VALUE_STRING);
+                }
+            }
+            int chars = (int) _inputBuffer[_inputPtr++];
+            int numeric = CharTypes.charToHex(chars);
+            if (numeric < 0) {
+                _reportUnexpectedChar(chars, "expected a hex-digit for character escape sequence");
+            }
+            result = (result << 4) | numeric;
+        }
+        return (char) result;
+    } /**
+     * Efficient handling for incremental parsing of base64-encoded
+     * textual content.
+     */
+    @SuppressWarnings("resource")
+    protected byte[] _decodeBase64ToByteArray(Base64Variant base64Variant) throws IOException
+    {
+        ByteArrayBuilder byteBuilder = _getByteArrayBuilder();
+
+        //main_loop:
+        while (true) {
+            // first, we'll skip preceding white space, if any
+            char chars;
+            do {
+                if (_inputPtr >= _inputEnd) {
+                    _ensureLoadMore();
+                }
+                chars = _inputBuffer[_inputPtr++];
+            } while (chars <= INT_SPACE);
+            int bitCount = base64Variant.decodeBase64Char(chars);
+            if (bitCount < 0) {
+                if (chars == '"') { // reached the end, fair and square?
+                    return byteBuilder.toByteArray();
+                }
+                bitCount = _decodeBase64Escape(base64Variant, chars, 0);
+                if (bitCount < 0) { // white space to skip
+                    continue;
+                }
+            }
+            int decodedValue = bitCount;
+
+            // then second base64 char; can't get padding yet, nor ws
+
+            if (_inputPtr >= _inputEnd) {
+                _ensureLoadMore();
+            }
+            chars = _inputBuffer[_inputPtr++];
+            bitCount = base64Variant.decodeBase64Char(chars);
+            if (bitCount < 0) {
+                bitCount = _decodeBase64Escape(base64Variant, chars, 1);
+            }
+            decodedValue = (decodedValue << 6) | bitCount;
+
+            // third base64 char; can be padding, but not ws
+            if (_inputPtr >= _inputEnd) {
+                _ensureLoadMore();
+            }
+            chars = _inputBuffer[_inputPtr++];
+            bitCount = base64Variant.decodeBase64Char(chars);
+
+            // First branch: can get padding (-> 1 byte)
+            if (bitCount < 0) {
+                if (bitCount != Base64Variant.BASE64_VALUE_PADDING) {
+                    // as per [JACKSON-631], could also just be 'missing'  padding
+                    if (chars == '"' && !base64Variant.usesPadding()) {
+                        decodedValue >>= 4;
+                        byteBuilder.append(decodedValue);
+                        return byteBuilder.toByteArray();
+                    }
+                    bitCount = _decodeBase64Escape(base64Variant, chars, 2);
+                }
+                if (bitCount == Base64Variant.BASE64_VALUE_PADDING) {
+                    // Ok, must get more padding chars, then
+                    if (_inputPtr >= _inputEnd) {
+                        _ensureLoadMore();
+                    }
+                    chars = _inputBuffer[_inputPtr++];
+                    if (!base64Variant.usesPaddingChar(chars)) {
+                        throw reportInvalidBase64Char(base64Variant, chars, 3, "expected padding character '"+ base64Variant.getPaddingChar()+"'");
+                    }
+                    // Got 12 bits, only need 8, need to shift
+                    decodedValue >>= 4;
+                    byteBuilder.append(decodedValue);
+                    continue;
+                }
+                // otherwise we got escaped other char, to be processed below
+            }
+            // Nope, 2 or 3 bytes
+            decodedValue = (decodedValue << 6) | bitCount;
+            // fourth and last base64 char; can be padding, but not ws
+            if (_inputPtr >= _inputEnd) {
+                _ensureLoadMore();
+            }
+            chars = _inputBuffer[_inputPtr++];
+            bitCount = base64Variant.decodeBase64Char(chars);
+            if (bitCount < 0) {
+                if (bitCount != Base64Variant.BASE64_VALUE_PADDING) {
+                    // as per [JACKSON-631], could also just be 'missing'  padding
+                    if (chars == '"' && !base64Variant.usesPadding()) {
+                        decodedValue >>= 2;
+                        byteBuilder.appendTwoBytes(decodedValue);
+                        return byteBuilder.toByteArray();
+                    }
+                    bitCount = _decodeBase64Escape(base64Variant, chars, 3);
+                }
+                if (bitCount == Base64Variant.BASE64_VALUE_PADDING) {
+                    // With padding we only get 2 bytes; but we have
+                    // to shift it a bit so it is identical to triplet
+                    // case with partial output.
+                    // 3 chars gives 3x6 == 18 bits, of which 2 are
+                    // dummies, need to discard:
+                    decodedValue >>= 2;
+                    byteBuilder.appendTwoBytes(decodedValue);
+                    continue;
+                }
+                // otherwise we got escaped other char, to be processed below
+            }
+            // otherwise, our triplet is now complete
+            decodedValue = (decodedValue << 6) | bitCount;
+            byteBuilder.appendThreeBytes(decodedValue);
+        }
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
+    }private void _closeContainer(int index) throws JsonParseException {
+        if (index == INT_RBRACKET) {
+            _updateTokenLocation();
+            if (!_parsingContext.inArray()) {
+                _reportMismatchedEndMarker(index, '}');
+            }
+            _parsingContext = _parsingContext.clearAndGetParent();
+            _currToken = JsonToken.END_ARRAY;
+        }
+        if (index == INT_RCURLY) {
+            _updateTokenLocation();
+            if (!_parsingContext.inObject()) {
+                _reportMismatchedEndMarker(index, ']');
+            }
+            _parsingContext = _parsingContext.clearAndGetParent();
+            _currToken = JsonToken.END_OBJECT;
+        }
+    } /**
+     * Method called when caller wants to provide input buffer directly,
+     * and it may or may not be recyclable use standard recycle context.
+     *
+     * @since 2.4
+     */
+    public JsonParserFromReader(IOContext ioContext, int featureFlags, Reader reader,
+                                ObjectCodec objectMapper, CharsToNameCanonicalizer symbolTable,
+                                char[] inputChars, int beginIndex, int limitIndex,
+                                boolean isRecyclable)
+    {
+        super(ioContext, featureFlags);
+        _reader = reader;
+        _inputBuffer = inputChars;
+        _inputPtr = beginIndex;
+        _inputEnd = limitIndex;
+        _objectCodec = objectMapper;
+        _symbols = symbolTable;
+        _hashSeed = symbolTable.hashSeed();
+        _bufferRecyclable = isRecyclable;
+    } /**
+     * Method called when input comes as a {@link java.io.Reader}, and buffer allocation
+     * can be done using default mechanism.
+     */
+    public JsonParserFromReader(IOContext ioContext, int featureFlags, Reader reader,
+                                ObjectCodec objectMapper, CharsToNameCanonicalizer symbolTable)
+    {
+        super(ioContext, featureFlags);
+        _reader = reader;
+        _inputBuffer = ioContext.allocTokenBuffer();
+        _inputPtr = 0;
+        _inputEnd = 0;
+        _objectCodec = objectMapper;
+        _symbols = symbolTable;
+        _hashSeed = symbolTable.hashSeed();
+        _bufferRecyclable = true;
+    }}
diff --git a/src/main/java/com/fasterxml/jackson/core/json/parsers/UTF8JsonInputParser.java b/src/main/java/com/fasterxml/jackson/core/json/parsers/UTF8JsonInputParser.java
new file mode 100644
index 00000000..a2939bea
--- /dev/null
+++ b/src/main/java/com/fasterxml/jackson/core/json/parsers/UTF8JsonInputParser.java
@@ -0,0 +1,2681 @@
+package com.fasterxml.jackson.core.json.parsers;
+
+import java.io.*;
+import java.util.Arrays;
+
+import com.fasterxml.jackson.core.*;
+import com.fasterxml.jackson.core.base.ParserBase;
+import com.fasterxml.jackson.core.io.CharTypes;
+import com.fasterxml.jackson.core.io.IOContext;
+import com.fasterxml.jackson.core.sym.ByteQuadsCanonicalizer;
+import com.fasterxml.jackson.core.util.*;
+
+import static com.fasterxml.jackson.core.JsonTokenId.*;
+
+/**
+ * This is a concrete implementation of {@link JsonParser}, which is
+ * based on a {@link java.io.DataInput} as the input source.
+ *<p>
+ * Due to limitations in look-ahead (basically there's none), as well
+ * as overhead of reading content mostly byte-by-byte,
+ * there are some
+ * minor differences from regular streaming parsing. Specifically:
+ *<ul>
+ * <li>Input location is not being tracked, as offsets would need to
+ *   be updated for each read from all over the place; if caller wants
+ *   this information, it has to track this with {@link DataInput}.
+ *  </li>
+ * <li>As a consequence linefeed handling is removed so all white-space is
+ *    equal; and checks are simplified NOT to check for control characters
+ *  </li>
+ * </ul>
+ *
+ * @since 2.8
+ */
+public class UTF8JsonInputParser
+    extends ParserBase
+{
+    final static byte LF_BYTE = (byte) '\n';
+
+    // This is the main input-code lookup table, fetched eagerly
+    private final static int[] UTF8_CHAR_CLASS_TABLE = CharTypes.getInputCodeUtf8();
+
+    // Latin1 encoding is not supported, but we do use 8-bit subset for
+    // pre-processing task, to simplify first pass, keep it fast.
+    protected final static int[] _icLatin1 = CharTypes.getInputCodeLatin1();
+
+    /*
+    /**********************************************************
+    /* Configuration
+    /**********************************************************
+     */
+
+    /**
+     * Codec used for data binding when (if) requested; typically full
+     * <code>ObjectMapper</code>, but that abstract is not part of core
+     * package.
+     */
+    protected ObjectCodec _objectCodec;
+
+    /**
+     * Symbol table that contains field names encountered so far
+     */
+    final protected ByteQuadsCanonicalizer _symbols;
+
+    /*
+    /**********************************************************
+    /* Parsing state
+    /**********************************************************
+     */
+
+    /**
+     * Temporary buffer used for name parsing.
+     */
+    protected int[] _quadBuffer = new int[16];
+
+    /**
+     * Flag that indicates that the current token has not yet
+     * been fully processed, and needs to be finished for
+     * some access (or skipped to obtain the next token)
+     */
+    protected boolean _tokenIncomplete;
+
+    /**
+     * Temporary storage for partially parsed name bytes.
+     */
+    private int firstQuad;
+
+    /*
+    /**********************************************************
+    /* Current input data
+    /**********************************************************
+     */
+
+    protected DataInput _inputData;
+
+    /**
+     * Sometimes we need buffering for just a single byte we read but
+     * have to "push back"
+     */
+    protected int _nextByte = -1;
+
+    /*
+    /**********************************************************
+    /* Life-cycle
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Overrides for life-cycle
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Overrides, low-level reading
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Public API, data access
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Public API, traversal, basic
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Public API, traversal, nextXxxValue/nextFieldName
+    /**********************************************************
+     */
+
+    // Can not implement without look-ahead...
+//    public boolean nextFieldName(SerializableString str) throws IOException
+
+    /*
+    /**********************************************************
+    /* Internal methods, number parsing
+    /**********************************************************
+     */
+
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
+
+    /*
+    /**********************************************************
+    /* Internal methods, String value parsing
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Internal methods, ws skipping, escape/unescape
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Internal methods,UTF8 decoding
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Internal methods, error reporting
+    /**********************************************************
+     */
+
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
+
+    private final void skipUtf8_4() throws IOException
+    {
+        int continuationByte = _inputData.readUnsignedByte();
+        if ((continuationByte & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(continuationByte & 0xFF);
+        }
+        continuationByte = _inputData.readUnsignedByte();
+        if ((continuationByte & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(continuationByte & 0xFF);
+        }
+        continuationByte = _inputData.readUnsignedByte();
+        if ((continuationByte & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(continuationByte & 0xFF);
+        }
+    }private final void skipUtf8_2() throws IOException
+    {
+        int currChar = _inputData.readUnsignedByte();
+        if ((currChar & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(currChar & 0xFF);
+        }
+    } /**
+     * Method called when we have seen one zero, and want to ensure
+     * it is not followed by another, or, if leading zeroes allowed,
+     * skipped redundant ones.
+     *
+     * @return Character immediately following zeroes
+     */
+    private final int skipLeadingZeroes() throws IOException
+    {
+        int charCode = _inputData.readUnsignedByte();
+        // if not followed by a number (probably '.'); return zero as is, to be included
+        if (charCode < INT_0 || charCode > INT_9) {
+            return charCode;
+        }
+        // we may want to allow leading zeroes them, after all...
+        if (!isEnabled(Feature.ALLOW_NUMERIC_LEADING_ZEROS)) {
+            reportInvalidNumber("Leading zeroes not allowed");
+        }
+        // if so, just need to skip either all zeroes (if followed by number); or all but one (if non-number)
+        while (charCode == INT_0) {
+            charCode = _inputData.readUnsignedByte();
+        }
+        return charCode;
+    } /**
+     * Helper method needed to fix [Issue#148], masking of 0x00 character
+     */
+    private final static int signExtend(int quoteChar, int byteCount) {
+        return (byteCount == 4) ? quoteChar : (quoteChar | (-1 << (byteCount << 3)));
+    }@Override
+    public void setCodec(ObjectCodec mapper) {
+        _objectCodec = mapper;
+    }@Override
+    public int releaseBufferedBytes(OutputStream destStream) throws IOException {
+        return 0;
+    }@Override
+    public int readBinaryValueToStream(Base64Variant base64Variant, OutputStream destStream) throws IOException
+    {
+        // if we have already read the token, just use whatever we may have
+        if (!_tokenIncomplete || _currToken != JsonToken.VALUE_STRING) {
+            byte[] byteBlock = getBinaryValue(base64Variant);
+            destStream.write(byteBlock);
+            return byteBlock.length;
+        }
+        // otherwise do "real" incremental parsing...
+        byte[] byteArray = _ioContext.allocBase64Buffer();
+        try {
+            return readBinary(base64Variant, destStream, byteArray);
+        } finally {
+            _ioContext.releaseBase64Buffer(byteArray);
+        }
+    }protected int readBinary(Base64Variant base64Variant, OutputStream destStream,
+                             byte[] byteArray) throws IOException
+    {
+        int writeIndex = 0;
+        final int endOffset = byteArray.length - 3;
+        int writtenCount = 0;
+
+        while (true) {
+            // first, we'll skip preceding white space, if any
+            int charCode;
+            do {
+                charCode = _inputData.readUnsignedByte();
+            } while (charCode <= INT_SPACE);
+            int bitCount = base64Variant.decodeBase64Char(charCode);
+            if (bitCount < 0) { // reached the end, fair and square?
+                if (charCode == INT_QUOTE) {
+                    break;
+                }
+                bitCount = _decodeBase64Escape(base64Variant, charCode, 0);
+                if (bitCount < 0) { // white space to skip
+                    continue;
+                }
+            }
+
+            // enough room? If not, flush
+            if (writeIndex > endOffset) {
+                writtenCount += writeIndex;
+                destStream.write(byteArray, 0, writeIndex);
+                writeIndex = 0;
+            }
+
+            int decodedValue = bitCount;
+
+            // then second base64 char; can't get padding yet, nor ws
+            charCode = _inputData.readUnsignedByte();
+            bitCount = base64Variant.decodeBase64Char(charCode);
+            if (bitCount < 0) {
+                bitCount = _decodeBase64Escape(base64Variant, charCode, 1);
+            }
+            decodedValue = (decodedValue << 6) | bitCount;
+
+            // third base64 char; can be padding, but not ws
+            charCode = _inputData.readUnsignedByte();
+            bitCount = base64Variant.decodeBase64Char(charCode);
+
+            // First branch: can get padding (-> 1 byte)
+            if (bitCount < 0) {
+                if (bitCount != Base64Variant.BASE64_VALUE_PADDING) {
+                    // could also just be 'missing'  padding
+                    if (charCode == '"' && !base64Variant.usesPadding()) {
+                        decodedValue >>= 4;
+                        byteArray[writeIndex++] = (byte) decodedValue;
+                        break;
+                    }
+                    bitCount = _decodeBase64Escape(base64Variant, charCode, 2);
+                }
+                if (bitCount == Base64Variant.BASE64_VALUE_PADDING) {
+                    // Ok, must get padding
+                    charCode = _inputData.readUnsignedByte();
+                    if (!base64Variant.usesPaddingChar(charCode)) {
+                        throw reportInvalidBase64Char(base64Variant, charCode, 3, "expected padding character '"+ base64Variant.getPaddingChar()+"'");
+                    }
+                    // Got 12 bits, only need 8, need to shift
+                    decodedValue >>= 4;
+                    byteArray[writeIndex++] = (byte) decodedValue;
+                    continue;
+                }
+            }
+            // Nope, 2 or 3 bytes
+            decodedValue = (decodedValue << 6) | bitCount;
+            // fourth and last base64 char; can be padding, but not ws
+            charCode = _inputData.readUnsignedByte();
+            bitCount = base64Variant.decodeBase64Char(charCode);
+            if (bitCount < 0) {
+                if (bitCount != Base64Variant.BASE64_VALUE_PADDING) {
+                    // could also just be 'missing'  padding
+                    if (charCode == '"' && !base64Variant.usesPadding()) {
+                        decodedValue >>= 2;
+                        byteArray[writeIndex++] = (byte) (decodedValue >> 8);
+                        byteArray[writeIndex++] = (byte) decodedValue;
+                        break;
+                    }
+                    bitCount = _decodeBase64Escape(base64Variant, charCode, 3);
+                }
+                if (bitCount == Base64Variant.BASE64_VALUE_PADDING) {
+                    /* With padding we only get 2 bytes; but we have
+                     * to shift it a bit so it is identical to triplet
+                     * case with partial output.
+                     * 3 chars gives 3x6 == 18 bits, of which 2 are
+                     * dummies, need to discard:
+                     */
+                    decodedValue >>= 2;
+                    byteArray[writeIndex++] = (byte) (decodedValue >> 8);
+                    byteArray[writeIndex++] = (byte) decodedValue;
+                    continue;
+                }
+            }
+            // otherwise, our triplet is now complete
+            decodedValue = (decodedValue << 6) | bitCount;
+            byteArray[writeIndex++] = (byte) (decodedValue >> 16);
+            byteArray[writeIndex++] = (byte) (decodedValue >> 8);
+            byteArray[writeIndex++] = (byte) decodedValue;
+        }
+        _tokenIncomplete = false;
+        if (writeIndex > 0) {
+            writtenCount += writeIndex;
+            destStream.write(byteArray, 0, writeIndex);
+        }
+        return writtenCount;
+    }private final String parseFieldName(int firstQuad, int charCode, int tailQuadBytes) throws IOException {
+        return parseEscapedFieldName(_quadBuffer, 0, firstQuad, charCode, tailQuadBytes);
+    }private final String parseFieldName(int firstQuad, int secondQuad, int charCode, int tailQuadBytes) throws IOException {
+        _quadBuffer[0] = firstQuad;
+        return parseEscapedFieldName(_quadBuffer, 1, secondQuad, charCode, tailQuadBytes);
+    }private final String parseFieldName(int firstQuad, int secondQuad, int thirdQuad, int charCode, int tailQuadBytes) throws IOException {
+        _quadBuffer[0] = firstQuad;
+        _quadBuffer[1] = secondQuad;
+        return parseEscapedFieldName(_quadBuffer, 2, thirdQuad, charCode, tailQuadBytes);
+    } /**
+     * Slower parsing method which is generally branched to when
+     * an escape sequence is detected (or alternatively for long
+     * names, one crossing input buffer boundary).
+     * Needs to be able to handle more exceptional cases, gets slower,
+     * and hance is offlined to a separate method.
+     */
+    protected final String parseEscapedFieldName(int[] quadArray, int quadLength, int activeQuad, int charCode,
+                                                 int quadByteCount) throws IOException
+    {
+        /* 25-Nov-2008, tatu: This may seem weird, but here we do not want to worry about
+         *   UTF-8 decoding yet. Rather, we'll assume that part is ok (if not it will get
+         *   caught later on), and just handle quotes and backslashes here.
+         */
+        final int[] codePoints = _icLatin1;
+
+        while (true) {
+            if (codePoints[charCode] != 0) {
+                if (charCode == INT_QUOTE) { // we are done
+                    break;
+                }
+                // Unquoted white space?
+                if (charCode != INT_BACKSLASH) {
+                    // As per [JACKSON-208], call can now return:
+                    _throwUnquotedSpace(charCode, "name");
+                } else {
+                    // Nope, escape sequence
+                    charCode = _decodeEscaped();
+                }
+                /* Oh crap. May need to UTF-8 (re-)encode it, if it's
+                 * beyond 7-bit ascii. Gets pretty messy.
+                 * If this happens often, may want to use different name
+                 * canonicalization to avoid these hits.
+                 */
+                if (charCode > 127) {
+                    // Ok, we'll need room for first byte right away
+                    if (quadByteCount >= 4) {
+                        if (quadLength >= quadArray.length) {
+                            _quadBuffer = quadArray = growArrayBy(quadArray, quadArray.length);
+                        }
+                        quadArray[quadLength++] = activeQuad;
+                        activeQuad = 0;
+                        quadByteCount = 0;
+                    }
+                    if (charCode < 0x800) { // 2-byte
+                        activeQuad = (activeQuad << 8) | (0xc0 | (charCode >> 6));
+                        ++quadByteCount;
+                        // Second byte gets output below:
+                    } else { // 3 bytes; no need to worry about surrogates here
+                        activeQuad = (activeQuad << 8) | (0xe0 | (charCode >> 12));
+                        ++quadByteCount;
+                        // need room for middle byte?
+                        if (quadByteCount >= 4) {
+                            if (quadLength >= quadArray.length) {
+                                _quadBuffer = quadArray = growArrayBy(quadArray, quadArray.length);
+                            }
+                            quadArray[quadLength++] = activeQuad;
+                            activeQuad = 0;
+                            quadByteCount = 0;
+                        }
+                        activeQuad = (activeQuad << 8) | (0x80 | ((charCode >> 6) & 0x3f));
+                        ++quadByteCount;
+                    }
+                    // And same last byte in both cases, gets output below:
+                    charCode = 0x80 | (charCode & 0x3f);
+                }
+            }
+            // Ok, we have one more byte to add at any rate:
+            if (quadByteCount < 4) {
+                ++quadByteCount;
+                activeQuad = (activeQuad << 8) | charCode;
+            } else {
+                if (quadLength >= quadArray.length) {
+                    _quadBuffer = quadArray = growArrayBy(quadArray, quadArray.length);
+                }
+                quadArray[quadLength++] = activeQuad;
+                activeQuad = charCode;
+                quadByteCount = 1;
+            }
+            charCode = _inputData.readUnsignedByte();
+        }
+
+        if (quadByteCount > 0) {
+            if (quadLength >= quadArray.length) {
+                _quadBuffer = quadArray = growArrayBy(quadArray, quadArray.length);
+            }
+            quadArray[quadLength++] = signExtend(activeQuad, quadByteCount);
+        }
+        String fieldName = _symbols.findName(quadArray, quadLength);
+        if (fieldName == null) {
+            fieldName = addNameFromUtf8(quadArray, quadLength, quadByteCount);
+        }
+        return fieldName;
+    }@Override
+    public String nextStringValue() throws IOException
+    {
+        // two distinct cases; either got name and we know next type, or 'other'
+        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
+            _nameCopied = false;
+            JsonToken token = _nextToken;
+            _nextToken = null;
+            _currToken = token;
+            if (token == JsonToken.VALUE_STRING) {
+                if (_tokenIncomplete) {
+                    _tokenIncomplete = false;
+                    return _finishAndGetString();
+                }
+                return _textBuffer.contentsAsString();
+            }
+            if (token == JsonToken.START_ARRAY) {
+                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            } else if (token == JsonToken.START_OBJECT) {
+                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            }
+            return null;
+        }
+        return (nextJsonToken() == JsonToken.VALUE_STRING) ? getText() : null;
+    }@Override
+    public String nextPropertyName() throws IOException
+    {
+        // // // Note: this is almost a verbatim copy of nextToken()
+
+        _numTypesValid = NR_UNKNOWN;
+        if (_currToken == JsonToken.FIELD_NAME) {
+            _nextAfterFieldName();
+            return null;
+        }
+        if (_tokenIncomplete) {
+            _skipStringValue();
+        }
+        int idx = _nextNonWhitespaceByte();
+        _binaryValue = null;
+        _tokenInputRow = _currInputRow;
+
+        if (idx == INT_RBRACKET) {
+            if (!_parsingContext.inArray()) {
+                _reportMismatchedEndMarker(idx, '}');
+            }
+            _parsingContext = _parsingContext.clearAndGetParent();
+            _currToken = JsonToken.END_ARRAY;
+            return null;
+        }
+        if (idx == INT_RCURLY) {
+            if (!_parsingContext.inObject()) {
+                _reportMismatchedEndMarker(idx, ']');
+            }
+            _parsingContext = _parsingContext.clearAndGetParent();
+            _currToken = JsonToken.END_OBJECT;
+            return null;
+        }
+
+        // Nope: do we then expect a comma?
+        if (_parsingContext.expectComma()) {
+            if (idx != INT_COMMA) {
+                _reportUnexpectedChar(idx, "was expecting comma to separate "+_parsingContext.typeDesc()+" entries");
+            }
+            idx = _nextNonWhitespaceByte();
+        }
+        if (!_parsingContext.inObject()) {
+            _nextTokenOutsideObject(idx);
+            return null;
+        }
+
+        final String nameString = _parseFieldName(idx);
+        _parsingContext.setCurrentName(nameString);
+        _currToken = JsonToken.FIELD_NAME;
+
+        idx = _consumeColon();
+        if (idx == INT_QUOTE) {
+            _tokenIncomplete = true;
+            _nextToken = JsonToken.VALUE_STRING;
+            return nameString;
+        }
+        JsonToken token;
+        switch (idx) {
+        case '-':
+            token = _parseNegativeNumber();
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
+            token = _parsePositiveNumber(idx);
+            break;
+        case 'f':
+            _matchJsonToken("false", 1);
+             token = JsonToken.VALUE_FALSE;
+            break;
+        case 'n':
+            _matchJsonToken("null", 1);
+            token = JsonToken.VALUE_NULL;
+            break;
+        case 't':
+            _matchJsonToken("true", 1);
+            token = JsonToken.VALUE_TRUE;
+            break;
+        case '[':
+            token = JsonToken.START_ARRAY;
+            break;
+        case '{':
+            token = JsonToken.START_OBJECT;
+            break;
+
+        default:
+            token = _handleInvalidValue(idx);
+        }
+        _nextToken = token;
+        return nameString;
+    }@Override
+    public long nextLongValueOrDefault(long fallback) throws IOException
+    {
+        // two distinct cases; either got name and we know next type, or 'other'
+        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
+            _nameCopied = false;
+            JsonToken token = _nextToken;
+            _nextToken = null;
+            _currToken = token;
+            if (token == JsonToken.VALUE_NUMBER_INT) {
+                return getLongValue();
+            }
+            if (token == JsonToken.START_ARRAY) {
+                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            } else if (token == JsonToken.START_OBJECT) {
+                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            }
+            return fallback;
+        }
+        return (nextJsonToken() == JsonToken.VALUE_NUMBER_INT) ? getLongValue() : fallback;
+    } /**
+     * @return Next token from the stream, if any found, or null
+     *   to indicate end-of-input
+     */
+    @Override
+    public JsonToken nextJsonToken() throws IOException
+    {
+        /* First: field names are special -- we will always tokenize
+         * (part of) value along with field name to simplify
+         * state handling. If so, can and need to use secondary token:
+         */
+        if (_currToken == JsonToken.FIELD_NAME) {
+            return _nextAfterFieldName();
+        }
+        // But if we didn't already have a name, and (partially?) decode number,
+        // need to ensure no numeric information is leaked
+        _numTypesValid = NR_UNKNOWN;
+        if (_tokenIncomplete) {
+            _skipStringValue(); // only strings can be partial
+        }
+        int idx = _skipWhitespaceOrEnd();
+        if (idx < 0) { // end-of-input
+            // Close/release things like input source, symbol table and recyclable buffers
+            close();
+            return (_currToken = null);
+        }
+        // clear any data retained so far
+        _binaryValue = null;
+        _tokenInputRow = _currInputRow;
+
+        // Closing scope?
+        if (idx == INT_RBRACKET || idx == INT_RCURLY) {
+            _closeCurrentScope(idx);
+            return _currToken;
+        }
+
+        // Nope: do we then expect a comma?
+        if (_parsingContext.expectComma()) {
+            if (idx != INT_COMMA) {
+                _reportUnexpectedChar(idx, "was expecting comma to separate "+_parsingContext.typeDesc()+" entries");
+            }
+            idx = _nextNonWhitespaceByte();
+
+            // Was that a trailing comma?
+            if (Feature.ALLOW_TRAILING_COMMA.enabledIn(_features)) {
+                if (idx == INT_RBRACKET || idx == INT_RCURLY) {
+                    _closeCurrentScope(idx);
+                    return _currToken;
+                }
+            }
+        }
+
+        /* And should we now have a name? Always true for
+         * Object contexts, since the intermediate 'expect-value'
+         * state is never retained.
+         */
+        if (!_parsingContext.inObject()) {
+            return _nextTokenOutsideObject(idx);
+        }
+        // So first parse the field name itself:
+        String name = _parseFieldName(idx);
+        _parsingContext.setCurrentName(name);
+        _currToken = JsonToken.FIELD_NAME;
+
+        idx = _consumeColon();
+
+        // Ok: we must have a value... what is it? Strings are very common, check first:
+        if (idx == INT_QUOTE) {
+            _tokenIncomplete = true;
+            _nextToken = JsonToken.VALUE_STRING;
+            return _currToken;
+        }
+        JsonToken token;
+
+        switch (idx) {
+        case '-':
+            token = _parseNegativeNumber();
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
+            token = _parsePositiveNumber(idx);
+            break;
+        case 'f':
+            _matchJsonToken("false", 1);
+             token = JsonToken.VALUE_FALSE;
+            break;
+        case 'n':
+            _matchJsonToken("null", 1);
+            token = JsonToken.VALUE_NULL;
+            break;
+        case 't':
+            _matchJsonToken("true", 1);
+            token = JsonToken.VALUE_TRUE;
+            break;
+        case '[':
+            token = JsonToken.START_ARRAY;
+            break;
+        case '{':
+            token = JsonToken.START_OBJECT;
+            break;
+
+        default:
+            token = _handleInvalidValue(idx);
+        }
+        _nextToken = token;
+        return _currToken;
+    }@Override
+    public int nextIntOrDefault(int fallback) throws IOException
+    {
+        // two distinct cases; either got name and we know next type, or 'other'
+        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
+            _nameCopied = false;
+            JsonToken token = _nextToken;
+            _nextToken = null;
+            _currToken = token;
+            if (token == JsonToken.VALUE_NUMBER_INT) {
+                return getIntValue();
+            }
+            if (token == JsonToken.START_ARRAY) {
+                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            } else if (token == JsonToken.START_OBJECT) {
+                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            }
+            return fallback;
+        }
+        return (nextJsonToken() == JsonToken.VALUE_NUMBER_INT) ? getIntValue() : fallback;
+    }@Override
+    public Boolean nextBoolean() throws IOException
+    {
+        // two distinct cases; either got name and we know next type, or 'other'
+        if (_currToken == JsonToken.FIELD_NAME) { // mostly copied from '_nextAfterName'
+            _nameCopied = false;
+            JsonToken token = _nextToken;
+            _nextToken = null;
+            _currToken = token;
+            if (token == JsonToken.VALUE_TRUE) {
+                return Boolean.TRUE;
+            }
+            if (token == JsonToken.VALUE_FALSE) {
+                return Boolean.FALSE;
+            }
+            if (token == JsonToken.START_ARRAY) {
+                _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            } else if (token == JsonToken.START_OBJECT) {
+                _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            }
+            return null;
+        }
+
+        JsonToken token = nextJsonToken();
+        if (token == JsonToken.VALUE_TRUE) {
+            return Boolean.TRUE;
+        }
+        if (token == JsonToken.VALUE_FALSE) {
+            return Boolean.FALSE;
+        }
+        return null;
+    }private static int[] growArrayBy(int[] array, int extra)
+    {
+        if (array == null) {
+            return new int[extra];
+        }
+        return Arrays.copyOf(array, array.length + extra);
+    }// // // Let's override default impls for improved performance
+    @Override
+    public String getValueAsString() throws IOException
+    {
+        if (_currToken == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                return _finishAndGetString(); // only strings can be incomplete
+            }
+            return _textBuffer.contentsAsString();
+        }
+        if (_currToken == JsonToken.FIELD_NAME) {
+            return getCurrentName();
+        }
+        return super.getValueAsString(null);
+    }@Override
+    public String getValueAsString(String defaultValue) throws IOException
+    {
+        if (_currToken == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                return _finishAndGetString(); // only strings can be incomplete
+            }
+            return _textBuffer.contentsAsString();
+        }
+        if (_currToken == JsonToken.FIELD_NAME) {
+            return getCurrentName();
+        }
+        return super.getValueAsString(defaultValue);
+    }@Override
+    public int getValueAsInt() throws IOException
+    {
+        JsonToken token = _currToken;
+        if ((token == JsonToken.VALUE_NUMBER_INT) || (token == JsonToken.VALUE_NUMBER_FLOAT)) {
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
+        }
+        return super.getValueAsInt(0);
+    }@Override
+    public int getValueAsInt(int defaultValue) throws IOException
+    {
+        JsonToken token = _currToken;
+        if ((token == JsonToken.VALUE_NUMBER_INT) || (token == JsonToken.VALUE_NUMBER_FLOAT)) {
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
+        }
+        return super.getValueAsInt(defaultValue);
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
+        }
+        return 0;
+    }@Override
+    public int getTextLength() throws IOException
+    {
+        if (_currToken == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                _finishString(); // only strings can be incomplete
+            }
+            return _textBuffer.size();
+        }
+        if (_currToken == JsonToken.FIELD_NAME) {
+            return _parsingContext.getCurrentName().length();
+        }
+        if (_currToken != null) { // null only before/after document
+            if (_currToken.isNumeric()) {
+                return _textBuffer.size();
+            }
+            return _currToken.asCharArray().length;
+        }
+        return 0;
+    }@Override
+    public char[] getTextCharacters() throws IOException
+    {
+        if (_currToken != null) { // null only before/after document
+            switch (_currToken.id()) {
+
+            case ID_FIELD_NAME:
+                if (!_nameCopied) {
+                    String fieldName = _parsingContext.getCurrentName();
+                    int nameLength = fieldName.length();
+                    if (_nameCopyBuffer == null) {
+                        _nameCopyBuffer = _ioContext.allocNameCopyBuffer(nameLength);
+                    } else if (_nameCopyBuffer.length < nameLength) {
+                        _nameCopyBuffer = new char[nameLength];
+                    }
+                    fieldName.getChars(0, nameLength, _nameCopyBuffer, 0);
+                    _nameCopied = true;
+                }
+                return _nameCopyBuffer;
+
+            case ID_STRING:
+                if (_tokenIncomplete) {
+                    _tokenIncomplete = false;
+                    _finishString(); // only strings can be incomplete
+                }
+                // fall through
+            case ID_NUMBER_INT:
+            case ID_NUMBER_FLOAT:
+                return _textBuffer.getTextBuffer();
+
+            default:
+                return _currToken.asCharArray();
+            }
+        }
+        return null;
+    }@Override
+    public String getText() throws IOException
+    {
+        if (_currToken == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                return _finishAndGetString(); // only strings can be incomplete
+            }
+            return _textBuffer.contentsAsString();
+        }
+        return _getText(_currToken);
+    }@Override
+    public int getText(Writer textSink) throws IOException
+    {
+        JsonToken token = _currToken;
+        if (token == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                _finishString(); // only strings can be incomplete
+            }
+            return _textBuffer.contentsToWriter(textSink);
+        }
+        if (token == JsonToken.FIELD_NAME) {
+            String textValue = _parsingContext.getCurrentName();
+            textSink.write(textValue);
+            return textValue.length();
+        }
+        if (token != null) {
+            if (token.isNumeric()) {
+                return _textBuffer.contentsToWriter(textSink);
+            }
+            char[] chars = token.asCharArray();
+            textSink.write(chars);
+            return chars.length;
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
+    public byte[] getBinaryValue(Base64Variant base64Scheme) throws IOException
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
+                _binaryValue = _decodeBase64ToBytes(base64Scheme);
+            } catch (IllegalArgumentException illegalArgumentEx) {
+                throw _constructError("Failed to decode VALUE_STRING as base64 ("+ base64Scheme +"): "+ illegalArgumentEx.getMessage());
+            }
+            /* let's clear incomplete only now; allows for accessing other
+             * textual content in error cases
+             */
+            _tokenIncomplete = false;
+        } else { // may actually require conversion...
+            if (_binaryValue == null) {
+                @SuppressWarnings("resource")
+                ByteArrayBuilder byteArrayBuf = _getByteArrayBuilder();
+                _decodeBase64(getText(), byteArrayBuf, base64Scheme);
+                _binaryValue = byteArrayBuf.toByteArray();
+            }
+        }
+        return _binaryValue;
+    }private final String findOrAddName(int firstQuad, int tailQuadBytes) throws JsonParseException
+    {
+        firstQuad = signExtend(firstQuad, tailQuadBytes);
+        // Usually we'll find it from the canonical symbol table already
+        String fieldName = _symbols.findName(firstQuad);
+        if (fieldName != null) {
+            return fieldName;
+        }
+        // If not, more work. We'll need add stuff to buffer
+        _quadBuffer[0] = firstQuad;
+        return addNameFromUtf8(_quadBuffer, 1, tailQuadBytes);
+    }private final String findOrAddName(int firstQuad, int secondQuad, int tailQuadBytes) throws JsonParseException
+    {
+        secondQuad = signExtend(secondQuad, tailQuadBytes);
+        // Usually we'll find it from the canonical symbol table already
+        String fieldName = _symbols.findName(firstQuad, secondQuad);
+        if (fieldName != null) {
+            return fieldName;
+        }
+        // If not, more work. We'll need add stuff to buffer
+        _quadBuffer[0] = firstQuad;
+        _quadBuffer[1] = secondQuad;
+        return addNameFromUtf8(_quadBuffer, 2, tailQuadBytes);
+    }private final String findOrAddName(int firstQuad, int secondQuad, int thirdQuad, int tailQuadBytes) throws JsonParseException
+    {
+        thirdQuad = signExtend(thirdQuad, tailQuadBytes);
+        String fieldName = _symbols.findName(firstQuad, secondQuad, thirdQuad);
+        if (fieldName != null) {
+            return fieldName;
+        }
+        int[] quadArray = _quadBuffer;
+        quadArray[0] = firstQuad;
+        quadArray[1] = secondQuad;
+        quadArray[2] = signExtend(thirdQuad, tailQuadBytes);
+        return addNameFromUtf8(quadArray, 3, tailQuadBytes);
+    }private final String findOrAddName(int[] quadArray, int quadLength, int finalQuad, int tailQuadBytes) throws JsonParseException
+    {
+        if (quadLength >= quadArray.length) {
+            _quadBuffer = quadArray = growArrayBy(quadArray, quadArray.length);
+        }
+        quadArray[quadLength++] = signExtend(finalQuad, tailQuadBytes);
+        String fieldName = _symbols.findName(quadArray, quadLength);
+        if (fieldName == null) {
+            return addNameFromUtf8(quadArray, quadLength, tailQuadBytes);
+        }
+        return fieldName;
+    }@Override
+    public void finalizeToken() throws IOException {
+        if (_tokenIncomplete) {
+            _tokenIncomplete = false;
+            _finishString(); // only strings can be incomplete
+        }
+    } /**
+     * @return Character value <b>minus 0x10000</c>; this so that caller
+     *    can readily expand it to actual surrogates
+     */
+    private final int decodeUtf8_4(int currChar) throws IOException
+    {
+        int continuationByte = _inputData.readUnsignedByte();
+        if ((continuationByte & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(continuationByte & 0xFF);
+        }
+        currChar = ((currChar & 0x07) << 6) | (continuationByte & 0x3F);
+        continuationByte = _inputData.readUnsignedByte();
+        if ((continuationByte & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(continuationByte & 0xFF);
+        }
+        currChar = (currChar << 6) | (continuationByte & 0x3F);
+        continuationByte = _inputData.readUnsignedByte();
+        if ((continuationByte & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(continuationByte & 0xFF);
+        }
+
+        /* note: won't change it to negative here, since caller
+         * already knows it'll need a surrogate
+         */
+        return ((currChar << 6) | (continuationByte & 0x3F)) - 0x10000;
+    }private final int decodeUtf8_3(int firstByte) throws IOException
+    {
+        firstByte &= 0x0F;
+        int continuationByte = _inputData.readUnsignedByte();
+        if ((continuationByte & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(continuationByte & 0xFF);
+        }
+        int currChar = (firstByte << 6) | (continuationByte & 0x3F);
+        continuationByte = _inputData.readUnsignedByte();
+        if ((continuationByte & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(continuationByte & 0xFF);
+        }
+        currChar = (currChar << 6) | (continuationByte & 0x3F);
+        return currChar;
+    }private final int decodeUtf8_2Bytes(int currChar) throws IOException
+    {
+        int continuationByte = _inputData.readUnsignedByte();
+        if ((continuationByte & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(continuationByte & 0xFF);
+        }
+        return ((currChar & 0x1F) << 6) | (continuationByte & 0x3F);
+    } /**
+     * This is the main workhorse method used when we take a symbol
+     * table miss. It needs to demultiplex individual bytes, decode
+     * multi-byte chars (if any), and then construct Name instance
+     * and add it to the symbol table.
+     */
+    private final String addNameFromUtf8(int[] quadArray, int quadLength, int tailQuadBytes) throws JsonParseException
+    {
+        /* Ok: must decode UTF-8 chars. No other validation is
+         * needed, since unescaping has been done earlier as necessary
+         * (as well as error reporting for unescaped control chars)
+         */
+        // 4 bytes per quad, except last one maybe less
+        int byteLength = (quadLength << 2) - 4 + tailQuadBytes;
+
+        /* And last one is not correctly aligned (leading zero bytes instead
+         * need to shift a bit, instead of trailing). Only need to shift it
+         * for UTF-8 decoding; need revert for storage (since key will not
+         * be aligned, to optimize lookup speed)
+         */
+        int finalQuad;
+
+        if (tailQuadBytes < 4) {
+            finalQuad = quadArray[quadLength -1];
+            // 8/16/24 bit left shift
+            quadArray[quadLength -1] = (finalQuad << ((4 - tailQuadBytes) << 3));
+        } else {
+            finalQuad = 0;
+        }
+
+        // Need some working space, TextBuffer works well:
+        char[] charBuffer = _textBuffer.emptyAndGetCurrentSegment();
+        int charIndex = 0;
+
+        for (int index = 0; index < byteLength; ) {
+            int charCode = quadArray[index >> 2]; // current quad, need to shift+mask
+            int byteIndex = (index & 3);
+            charCode = (charCode >> ((3 - byteIndex) << 3)) & 0xFF;
+            ++index;
+
+            if (charCode > 127) { // multi-byte
+                int requiredSize;
+                if ((charCode & 0xE0) == 0xC0) { // 2 bytes (0x0080 - 0x07FF)
+                    charCode &= 0x1F;
+                    requiredSize = 1;
+                } else if ((charCode & 0xF0) == 0xE0) { // 3 bytes (0x0800 - 0xFFFF)
+                    charCode &= 0x0F;
+                    requiredSize = 2;
+                } else if ((charCode & 0xF8) == 0xF0) { // 4 bytes; double-char with surrogates and all...
+                    charCode &= 0x07;
+                    requiredSize = 3;
+                } else { // 5- and 6-byte chars not valid xml chars
+                    _reportInvalidInitialByte(charCode);
+                    requiredSize = charCode = 1; // never really gets this far
+                }
+                if ((index + requiredSize) > byteLength) {
+                    _reportInvalidEOF(" in field name", JsonToken.FIELD_NAME);
+                }
+
+                // Ok, always need at least one more:
+                int nextCharCode = quadArray[index >> 2]; // current quad, need to shift+mask
+                byteIndex = (index & 3);
+                nextCharCode = (nextCharCode >> ((3 - byteIndex) << 3));
+                ++index;
+
+                if ((nextCharCode & 0xC0) != 0x080) {
+                    _reportInvalidMiddleByte(nextCharCode);
+                }
+                charCode = (charCode << 6) | (nextCharCode & 0x3F);
+                if (requiredSize > 1) {
+                    nextCharCode = quadArray[index >> 2];
+                    byteIndex = (index & 3);
+                    nextCharCode = (nextCharCode >> ((3 - byteIndex) << 3));
+                    ++index;
+
+                    if ((nextCharCode & 0xC0) != 0x080) {
+                        _reportInvalidMiddleByte(nextCharCode);
+                    }
+                    charCode = (charCode << 6) | (nextCharCode & 0x3F);
+                    if (requiredSize > 2) { // 4 bytes? (need surrogates on output)
+                        nextCharCode = quadArray[index >> 2];
+                        byteIndex = (index & 3);
+                        nextCharCode = (nextCharCode >> ((3 - byteIndex) << 3));
+                        ++index;
+                        if ((nextCharCode & 0xC0) != 0x080) {
+                            _reportInvalidMiddleByte(nextCharCode & 0xFF);
+                        }
+                        charCode = (charCode << 6) | (nextCharCode & 0x3F);
+                    }
+                }
+                if (requiredSize > 2) { // surrogate pair? once again, let's output one here, one later on
+                    charCode -= 0x10000; // to normalize it starting with 0x0
+                    if (charIndex >= charBuffer.length) {
+                        charBuffer = _textBuffer.expandCurrentSegment();
+                    }
+                    charBuffer[charIndex++] = (char) (0xD800 + (charCode >> 10));
+                    charCode = 0xDC00 | (charCode & 0x03FF);
+                }
+            }
+            if (charIndex >= charBuffer.length) {
+                charBuffer = _textBuffer.expandCurrentSegment();
+            }
+            charBuffer[charIndex++] = (char) charCode;
+        }
+
+        // Ok. Now we have the character array, and can construct the String
+        String nameBase = new String(charBuffer, 0, charIndex);
+        // And finally, un-align if necessary
+        if (tailQuadBytes < 4) {
+            quadArray[quadLength -1] = finalQuad;
+        }
+        return _symbols.addName(nameBase, quadArray, quadLength);
+    } /**
+     * Method called to ensure that a root-value is followed by a space token,
+     * if possible.
+     *<p>
+     * NOTE: with {@link DataInput} source, not really feasible, up-front.
+     * If we did want, we could rearrange things to require space before
+     * next read, but initially let's just do nothing.
+     */
+    private final void _verifyRootWhitespace() throws IOException
+    {
+        int charCode = _nextByte;
+        if (charCode <= INT_SPACE) {
+            _nextByte = -1;
+            if (charCode == INT_CR || charCode == INT_LF) {
+                ++_currInputRow;
+            }
+            return;
+        }
+        _reportMissingRootWS(charCode);
+    }private final void _verifyMatchEnd(String expectedToken, int idx, int charCode) throws IOException {
+        // but actually only alphanums are problematic
+        char currChar = (char) _decodeUtf8CharForError(charCode);
+        if (Character.isJavaIdentifierPart(currChar)) {
+            _reportUnexpectedToken(currChar, expectedToken.substring(0, idx));
+        }
+    }private final boolean _skipYamlComment() throws IOException
+    {
+        if (!isEnabled(Feature.ALLOW_YAML_COMMENTS)) {
+            return false;
+        }
+        _skipLineComment();
+        return true;
+    } /**
+     * Alternative to {@link #_nextNonWhitespaceByte} that handles possible {@link EOFException}
+     * caused by trying to read past the end of {@link InputData}.
+     *
+     * @since 2.9
+     */
+    private final int _skipWhitespaceOrEnd() throws IOException
+    {
+        int idx = _nextByte;
+        if (idx < 0) {
+            try {
+                idx = _inputData.readUnsignedByte();
+            } catch (EOFException eofException) {
+                return _eofAsNextChar();
+            }
+        } else {
+            _nextByte = -1;
+        }
+        while (true) {
+            if (idx > INT_SPACE) {
+                if (idx == INT_SLASH || idx == INT_HASH) {
+                    return _skipWhitespaceAndComments(idx);
+                }
+                return idx;
+            } else {
+                // 06-May-2016, tatu: Could verify validity of WS, but for now why bother.
+                //   ... but line number is useful thingy
+                if (idx == INT_CR || idx == INT_LF) {
+                    ++_currInputRow;
+                }
+            }
+            try {
+                idx = _inputData.readUnsignedByte();
+            } catch (EOFException eofException) {
+                return _eofAsNextChar();
+            }
+        }
+    }private final int _skipWhitespaceAndComments(int idx) throws IOException
+    {
+        while (true) {
+            if (idx > INT_SPACE) {
+                if (idx == INT_SLASH) {
+                    _skipSlashComment();
+                } else if (idx == INT_HASH) {
+                    if (!_skipYamlComment()) {
+                        return idx;
+                    }
+                } else {
+                    return idx;
+                }
+            } else {
+                // 06-May-2016, tatu: Could verify validity of WS, but for now why bother.
+                //   ... but line number is useful thingy
+                if (idx == INT_CR || idx == INT_LF) {
+                    ++_currInputRow;
+                }
+                /*
+                if ((i != INT_SPACE) && (i != INT_LF) && (i != INT_CR)) {
+                    _throwInvalidSpace(i);
+                }
+                */
+            }
+            idx = _inputData.readUnsignedByte();
+        }
+    }/* Alas, can't heavily optimize skipping, since we still have to
+     * do validity checks...
+     */
+    private final void _skipUtf8_3Bytes() throws IOException
+    {
+        //c &= 0x0F;
+        int currChar = _inputData.readUnsignedByte();
+        if ((currChar & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(currChar & 0xFF);
+        }
+        currChar = _inputData.readUnsignedByte();
+        if ((currChar & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(currChar & 0xFF);
+        }
+    } /**
+     * Method called to skim through rest of unparsed String value,
+     * if it is not needed. This can be done bit faster if contents
+     * need not be stored for future access.
+     */
+    protected void _skipStringValue() throws IOException
+    {
+        _tokenIncomplete = false;
+
+        // Need to be fully UTF-8 aware here:
+        final int[] codePoints = UTF8_CHAR_CLASS_TABLE;
+
+        main_loop:
+        while (true) {
+            int currChar;
+
+            ascii_loop:
+            while (true) {
+                currChar = _inputData.readUnsignedByte();
+                if (codePoints[currChar] != 0) {
+                    break ascii_loop;
+                }
+            }
+            // Ok: end marker, escape or multi-byte?
+            if (currChar == INT_QUOTE) {
+                break main_loop;
+            }
+
+            switch (codePoints[currChar]) {
+            case 1: // backslash
+                _decodeEscaped();
+                break;
+            case 2: // 2-byte UTF
+                skipUtf8_2();
+                break;
+            case 3: // 3-byte UTF
+                _skipUtf8_3Bytes();
+                break;
+            case 4: // 4-byte UTF
+                skipUtf8_4();
+                break;
+            default:
+                if (currChar < INT_SPACE) {
+                    _throwUnquotedSpace(currChar, "string value");
+                } else {
+                    // Is this good enough error message?
+                    _reportInvalidCharacter(currChar);
+                }
+            }
+        }
+    }private final void _skipSlashComment() throws IOException
+    {
+        if (!isEnabled(Feature.ALLOW_COMMENTS)) {
+            _reportUnexpectedChar('/', "maybe a (non-standard) comment? (not recognized as one since Feature 'ALLOW_COMMENTS' not enabled for parser)");
+        }
+        int currChar = _inputData.readUnsignedByte();
+        if (currChar == '/') {
+            _skipLineComment();
+        } else if (currChar == '*') {
+            _skipCStyleComment();
+        } else {
+            _reportUnexpectedChar(currChar, "was expecting either '*' or '/' for a comment");
+        }
+    } /**
+     * Method for skipping contents of an input line; usually for CPP
+     * and YAML style comments.
+     */
+    private final void _skipLineComment() throws IOException
+    {
+        // Ok: need to find EOF or linefeed
+        final int[] codePoints = CharTypes.getInputCodeComment();
+        while (true) {
+            int idx = _inputData.readUnsignedByte();
+            int currentCode = codePoints[idx];
+            if (currentCode != 0) {
+                switch (currentCode) {
+                case INT_LF:
+                case INT_CR:
+                    ++_currInputRow;
+                    return;
+                case '*': // nop for these comments
+                    break;
+                case 2: // 2-byte UTF
+                    skipUtf8_2();
+                    break;
+                case 3: // 3-byte UTF
+                    _skipUtf8_3Bytes();
+                    break;
+                case 4: // 4-byte UTF
+                    skipUtf8_4();
+                    break;
+                default: // e.g. -1
+                    if (currentCode < 0) {
+                        // Is this good enough error message?
+                        _reportInvalidCharacter(idx);
+                    }
+                }
+            }
+        }
+    }private final int _skipColon(int idx, boolean hasColon) throws IOException
+    {
+        for (;; idx = _inputData.readUnsignedByte()) {
+            if (idx > INT_SPACE) {
+                if (idx == INT_SLASH) {
+                    _skipSlashComment();
+                    continue;
+                }
+                if (idx == INT_HASH) {
+                    if (_skipYamlComment()) {
+                        continue;
+                    }
+                }
+                if (hasColon) {
+                    return idx;
+                }
+                if (idx != INT_COLON) {
+                    _reportUnexpectedChar(idx, "was expecting a colon to separate field name and value");
+                }
+                hasColon = true;
+            } else {
+                // 06-May-2016, tatu: Could verify validity of WS, but for now why bother.
+                //   ... but line number is useful thingy
+                if (idx == INT_CR || idx == INT_LF) {
+                    ++_currInputRow;
+                }
+            }
+        }
+    }private final void _skipCStyleComment() throws IOException
+    {
+        // Need to be UTF-8 aware here to decode content (for skipping)
+        final int[] codePoints = CharTypes.getInputCodeComment();
+        int idx = _inputData.readUnsignedByte();
+
+        // Ok: need the matching '*/'
+        main_loop:
+        while (true) {
+            int currentCode = codePoints[idx];
+            if (currentCode != 0) {
+                switch (currentCode) {
+                case '*':
+                    idx = _inputData.readUnsignedByte();
+                    if (idx == INT_SLASH) {
+                        return;
+                    }
+                    continue main_loop;
+                case INT_LF:
+                case INT_CR:
+                    ++_currInputRow;
+                    break;
+                case 2: // 2-byte UTF
+                    skipUtf8_2();
+                    break;
+                case 3: // 3-byte UTF
+                    _skipUtf8_3Bytes();
+                    break;
+                case 4: // 4-byte UTF
+                    skipUtf8_4();
+                    break;
+                default: // e.g. -1
+                    // Is this good enough error message?
+                    _reportInvalidCharacter(idx);
+                }
+            }
+            idx = _inputData.readUnsignedByte();
+        }
+    }protected void _reportUnexpectedToken(int charCode, String matchedSegment) throws IOException
+     {
+         _reportUnexpectedToken(charCode, matchedSegment, "'null', 'true', 'false' or NaN");
+     }protected void _reportUnexpectedToken(int charCode, String matchedSegment, String message)
+        throws IOException
+     {
+         StringBuilder builder = new StringBuilder(matchedSegment);
+
+         /* Let's just try to find what appears to be the token, using
+          * regular Java identifier character rules. It's just a heuristic,
+          * nothing fancy here (nor fast).
+          */
+         while (true) {
+             char currChar = (char) _decodeUtf8CharForError(charCode);
+             if (!Character.isJavaIdentifierPart(currChar)) {
+                 break;
+             }
+             builder.append(currChar);
+             charCode = _inputData.readUnsignedByte();
+         }
+         _reportError("Unrecognized token '"+ builder.toString()+"': was expecting "+ message);
+     }private void _reportInvalidMiddleByte(int bitmask)
+        throws JsonParseException
+    {
+        _reportError("Invalid UTF-8 middle byte 0x"+Integer.toHexString(bitmask));
+    }protected void _reportInvalidInitialByte(int bitmask)
+        throws JsonParseException
+    {
+        _reportError("Invalid UTF-8 start byte 0x"+Integer.toHexString(bitmask));
+    }protected void _reportInvalidCharacter(int currChar)
+        throws JsonParseException
+    {
+        // Either invalid WS or illegal UTF-8 start char
+        if (currChar < INT_SPACE) {
+            _throwInvalidSpace(currChar);
+        }
+        _reportInvalidInitialByte(currChar);
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
+    protected JsonToken _parsePositiveNumber(int currChar) throws IOException
+    {
+        char[] charBuffer = _textBuffer.emptyAndGetCurrentSegment();
+        int charIndex;
+
+        // One special case: if first char is 0, must not be followed by a digit.
+        // Gets bit tricky as we only want to retain 0 if it's the full value
+        if (currChar == INT_0) {
+            currChar = skipLeadingZeroes();
+            if (currChar <= INT_9 && currChar >= INT_0) { // skip if followed by digit
+                charIndex = 0;
+            } else {
+                charBuffer[0] = '0';
+                charIndex = 1;
+            }
+        } else {
+            charBuffer[0] = (char) currChar;
+            currChar = _inputData.readUnsignedByte();
+            charIndex = 1;
+        }
+        int integerLength = charIndex;
+
+        // With this, we have a nice and tight loop:
+        while (currChar <= INT_9 && currChar >= INT_0) {
+            ++integerLength;
+            charBuffer[charIndex++] = (char) currChar;
+            currChar = _inputData.readUnsignedByte();
+        }
+        if (currChar == '.' || currChar == 'e' || currChar == 'E') {
+            return _parseFloatingPointNumber(charBuffer, charIndex, currChar, false, integerLength);
+        }
+        _textBuffer.setCurrentLength(charIndex);
+        // As per [core#105], need separating space between root values; check here
+        if (_parsingContext.inRoot()) {
+            _verifyRootWhitespace();
+        } else {
+            _nextByte = currChar;
+        }
+        // And there we have it!
+        return resetInt(false, integerLength);
+    }protected JsonToken _parseNegativeNumber() throws IOException
+    {
+        char[] charBuffer = _textBuffer.emptyAndGetCurrentSegment();
+        int charIndex = 0;
+
+        // Need to prepend sign?
+        charBuffer[charIndex++] = '-';
+        int currChar = _inputData.readUnsignedByte();
+        charBuffer[charIndex++] = (char) currChar;
+        // Note: must be followed by a digit
+        if (currChar <= INT_0) {
+            // One special case: if first char is 0 need to check no leading zeroes
+            if (currChar == INT_0) {
+                currChar = skipLeadingZeroes();
+            } else {
+                return _handleInvalidNumberTokenStart(currChar, true);
+            }
+        } else {
+            if (currChar > INT_9) {
+                return _handleInvalidNumberTokenStart(currChar, true);
+            }
+            currChar = _inputData.readUnsignedByte();
+        }
+        // Ok: we can first just add digit we saw first:
+        int integerLength = 1;
+
+        // With this, we have a nice and tight loop:
+        while (currChar <= INT_9 && currChar >= INT_0) {
+            ++integerLength;
+            charBuffer[charIndex++] = (char) currChar;
+            currChar = _inputData.readUnsignedByte();
+        }
+        if (currChar == '.' || currChar == 'e' || currChar == 'E') {
+            return _parseFloatingPointNumber(charBuffer, charIndex, currChar, true, integerLength);
+        }
+        _textBuffer.setCurrentLength(charIndex);
+        // As per [core#105], need separating space between root values; check here
+        _nextByte = currChar;
+        if (_parsingContext.inRoot()) {
+            _verifyRootWhitespace();
+        }
+        // And there we have it!
+        return resetInt(true, integerLength);
+    }private final String _parseMediumName(int thirdQuad, final int secondQuad) throws IOException
+    {
+        final int[] codePoints = _icLatin1;
+
+        // Got 9 name bytes so far
+        int idx = _inputData.readUnsignedByte();
+        if (codePoints[idx] != 0) {
+            if (idx == INT_QUOTE) { // 9 bytes
+                return findOrAddName(firstQuad, secondQuad, thirdQuad, 1);
+            }
+            return parseFieldName(firstQuad, secondQuad, thirdQuad, idx, 1);
+        }
+        thirdQuad = (thirdQuad << 8) | idx;
+        idx = _inputData.readUnsignedByte();
+        if (codePoints[idx] != 0) {
+            if (idx == INT_QUOTE) { // 10 bytes
+                return findOrAddName(firstQuad, secondQuad, thirdQuad, 2);
+            }
+            return parseFieldName(firstQuad, secondQuad, thirdQuad, idx, 2);
+        }
+        thirdQuad = (thirdQuad << 8) | idx;
+        idx = _inputData.readUnsignedByte();
+        if (codePoints[idx] != 0) {
+            if (idx == INT_QUOTE) { // 11 bytes
+                return findOrAddName(firstQuad, secondQuad, thirdQuad, 3);
+            }
+            return parseFieldName(firstQuad, secondQuad, thirdQuad, idx, 3);
+        }
+        thirdQuad = (thirdQuad << 8) | idx;
+        idx = _inputData.readUnsignedByte();
+        if (codePoints[idx] != 0) {
+            if (idx == INT_QUOTE) { // 12 bytes
+                return findOrAddName(firstQuad, secondQuad, thirdQuad, 4);
+            }
+            return parseFieldName(firstQuad, secondQuad, thirdQuad, idx, 4);
+        }
+        return _parseLongFieldName(idx, secondQuad, thirdQuad);
+    }private final String _parseMediumFieldName(int secondQuad) throws IOException
+    {
+        final int[] codePoints = _icLatin1;
+
+        // Ok, got 5 name bytes so far
+        int idx = _inputData.readUnsignedByte();
+        if (codePoints[idx] != 0) {
+            if (idx == INT_QUOTE) { // 5 bytes
+                return findOrAddName(firstQuad, secondQuad, 1);
+            }
+            return parseFieldName(firstQuad, secondQuad, idx, 1); // quoting or invalid char
+        }
+        secondQuad = (secondQuad << 8) | idx;
+        idx = _inputData.readUnsignedByte();
+        if (codePoints[idx] != 0) {
+            if (idx == INT_QUOTE) { // 6 bytes
+                return findOrAddName(firstQuad, secondQuad, 2);
+            }
+            return parseFieldName(firstQuad, secondQuad, idx, 2);
+        }
+        secondQuad = (secondQuad << 8) | idx;
+        idx = _inputData.readUnsignedByte();
+        if (codePoints[idx] != 0) {
+            if (idx == INT_QUOTE) { // 7 bytes
+                return findOrAddName(firstQuad, secondQuad, 3);
+            }
+            return parseFieldName(firstQuad, secondQuad, idx, 3);
+        }
+        secondQuad = (secondQuad << 8) | idx;
+        idx = _inputData.readUnsignedByte();
+        if (codePoints[idx] != 0) {
+            if (idx == INT_QUOTE) { // 8 bytes
+                return findOrAddName(firstQuad, secondQuad, 4);
+            }
+            return parseFieldName(firstQuad, secondQuad, idx, 4);
+        }
+        return _parseMediumName(idx, secondQuad);
+    }private final String _parseLongFieldName(int quoteChar, final int secondQuad, int thirdQuad) throws IOException
+    {
+        _quadBuffer[0] = firstQuad;
+        _quadBuffer[1] = secondQuad;
+        _quadBuffer[2] = thirdQuad;
+
+        // As explained above, will ignore UTF-8 encoding at this point
+        final int[] codePoints = _icLatin1;
+        int quadLength = 3;
+
+        while (true) {
+            int idx = _inputData.readUnsignedByte();
+            if (codePoints[idx] != 0) {
+                if (idx == INT_QUOTE) {
+                    return findOrAddName(_quadBuffer, quadLength, quoteChar, 1);
+                }
+                return parseEscapedFieldName(_quadBuffer, quadLength, quoteChar, idx, 1);
+            }
+
+            quoteChar = (quoteChar << 8) | idx;
+            idx = _inputData.readUnsignedByte();
+            if (codePoints[idx] != 0) {
+                if (idx == INT_QUOTE) {
+                    return findOrAddName(_quadBuffer, quadLength, quoteChar, 2);
+                }
+                return parseEscapedFieldName(_quadBuffer, quadLength, quoteChar, idx, 2);
+            }
+
+            quoteChar = (quoteChar << 8) | idx;
+            idx = _inputData.readUnsignedByte();
+            if (codePoints[idx] != 0) {
+                if (idx == INT_QUOTE) {
+                    return findOrAddName(_quadBuffer, quadLength, quoteChar, 3);
+                }
+                return parseEscapedFieldName(_quadBuffer, quadLength, quoteChar, idx, 3);
+            }
+
+            quoteChar = (quoteChar << 8) | idx;
+            idx = _inputData.readUnsignedByte();
+            if (codePoints[idx] != 0) {
+                if (idx == INT_QUOTE) {
+                    return findOrAddName(_quadBuffer, quadLength, quoteChar, 4);
+                }
+                return parseEscapedFieldName(_quadBuffer, quadLength, quoteChar, idx, 4);
+            }
+
+            // Nope, no end in sight. Need to grow quad array etc
+            if (quadLength >= _quadBuffer.length) {
+                _quadBuffer = growArrayBy(_quadBuffer, quadLength);
+            }
+            _quadBuffer[quadLength++] = quoteChar;
+            quoteChar = idx;
+        }
+    }private final JsonToken _parseFloatingPointNumber(char[] charBuffer, int charIndex, int currChar,
+                                                      boolean isNegative, int intPartLength) throws IOException
+    {
+        int fractionLength = 0;
+
+        // And then see if we get other parts
+        if (currChar == INT_PERIOD) { // yes, fraction
+            charBuffer[charIndex++] = (char) currChar;
+
+            fract_loop:
+            while (true) {
+                currChar = _inputData.readUnsignedByte();
+                if (currChar < INT_0 || currChar > INT_9) {
+                    break fract_loop;
+                }
+                ++fractionLength;
+                if (charIndex >= charBuffer.length) {
+                    charBuffer = _textBuffer.finishCurrentSegment();
+                    charIndex = 0;
+                }
+                charBuffer[charIndex++] = (char) currChar;
+            }
+            // must be followed by sequence of ints, one minimum
+            if (fractionLength == 0) {
+                reportUnexpectedNumberChar(currChar, "Decimal point not followed by a digit");
+            }
+        }
+
+        int exponentLength = 0;
+        if (currChar == INT_e || currChar == INT_E) { // exponent?
+            if (charIndex >= charBuffer.length) {
+                charBuffer = _textBuffer.finishCurrentSegment();
+                charIndex = 0;
+            }
+            charBuffer[charIndex++] = (char) currChar;
+            currChar = _inputData.readUnsignedByte();
+            // Sign indicator?
+            if (currChar == '-' || currChar == '+') {
+                if (charIndex >= charBuffer.length) {
+                    charBuffer = _textBuffer.finishCurrentSegment();
+                    charIndex = 0;
+                }
+                charBuffer[charIndex++] = (char) currChar;
+                currChar = _inputData.readUnsignedByte();
+            }
+            while (currChar <= INT_9 && currChar >= INT_0) {
+                ++exponentLength;
+                if (charIndex >= charBuffer.length) {
+                    charBuffer = _textBuffer.finishCurrentSegment();
+                    charIndex = 0;
+                }
+                charBuffer[charIndex++] = (char) currChar;
+                currChar = _inputData.readUnsignedByte();
+            }
+            // must be followed by sequence of ints, one minimum
+            if (exponentLength == 0) {
+                reportUnexpectedNumberChar(currChar, "Exponent indicator not followed by a digit");
+            }
+        }
+
+        // Ok; unless we hit end-of-input, need to push last char read back
+        // As per #105, need separating space between root values; check here
+        _nextByte = currChar;
+        if (_parsingContext.inRoot()) {
+            _verifyRootWhitespace();
+        }
+        _textBuffer.setCurrentLength(charIndex);
+
+        // And there we have it!
+        return resetFloat(isNegative, intPartLength, fractionLength, exponentLength);
+    }protected final String _parseFieldName(int idx) throws IOException
+    {
+        if (idx != INT_QUOTE) {
+            return _handleUnquotedName(idx);
+        }
+        // If so, can also unroll loops nicely
+        /* 25-Nov-2008, tatu: This may seem weird, but here we do
+         *   NOT want to worry about UTF-8 decoding. Rather, we'll
+         *   assume that part is ok (if not it will get caught
+         *   later on), and just handle quotes and backslashes here.
+         */
+        final int[] codePoints = _icLatin1;
+
+        int quoteChar = _inputData.readUnsignedByte();
+
+        if (codePoints[quoteChar] == 0) {
+            idx = _inputData.readUnsignedByte();
+            if (codePoints[idx] == 0) {
+                quoteChar = (quoteChar << 8) | idx;
+                idx = _inputData.readUnsignedByte();
+                if (codePoints[idx] == 0) {
+                    quoteChar = (quoteChar << 8) | idx;
+                    idx = _inputData.readUnsignedByte();
+                    if (codePoints[idx] == 0) {
+                        quoteChar = (quoteChar << 8) | idx;
+                        idx = _inputData.readUnsignedByte();
+                        if (codePoints[idx] == 0) {
+                            firstQuad = quoteChar;
+                            return _parseMediumFieldName(idx);
+                        }
+                        if (idx == INT_QUOTE) { // 4 byte/char case or broken
+                            return findOrAddName(quoteChar, 4);
+                        }
+                        return parseFieldName(quoteChar, idx, 4);
+                    }
+                    if (idx == INT_QUOTE) { // 3 byte/char case or broken
+                        return findOrAddName(quoteChar, 3);
+                    }
+                    return parseFieldName(quoteChar, idx, 3);
+                }
+                if (idx == INT_QUOTE) { // 2 byte/char case or broken
+                    return findOrAddName(quoteChar, 2);
+                }
+                return parseFieldName(quoteChar, idx, 2);
+            }
+            if (idx == INT_QUOTE) { // one byte/char case or broken
+                return findOrAddName(quoteChar, 1);
+            }
+            return parseFieldName(quoteChar, idx, 1);
+        }
+        if (quoteChar == INT_QUOTE) { // special case, ""
+            return "";
+        }
+        return parseFieldName(0, quoteChar, 0); // quoting or invalid char
+    }/* Parsing to allow optional use of non-standard single quotes.
+     * Plenty of duplicated code;
+     * main reason being to try to avoid slowing down fast path
+     * for valid JSON -- more alternatives, more code, generally
+     * bit slower execution.
+     */
+    protected String _parseApostropheName() throws IOException
+    {
+        int charCode = _inputData.readUnsignedByte();
+        if (charCode == '\'') { // special case, ''
+            return "";
+        }
+        int[] quadArray = _quadBuffer;
+        int quadLength = 0;
+        int activeQuad = 0;
+        int quadByteCount = 0;
+
+        // Copied from parseEscapedFieldName, with minor mods:
+
+        final int[] codePoints = _icLatin1;
+
+        while (true) {
+            if (charCode == '\'') {
+                break;
+            }
+            // additional check to skip handling of double-quotes
+            if (charCode != '"' && codePoints[charCode] != 0) {
+                if (charCode != '\\') {
+                    // Unquoted white space?
+                    // As per [JACKSON-208], call can now return:
+                    _throwUnquotedSpace(charCode, "name");
+                } else {
+                    // Nope, escape sequence
+                    charCode = _decodeEscaped();
+                }
+                /* Oh crap. May need to UTF-8 (re-)encode it, if it's  beyond
+                 * 7-bit ASCII. Gets pretty messy. If this happens often, may want
+                 * to use different name canonicalization to avoid these hits.
+                 */
+                if (charCode > 127) {
+                    // Ok, we'll need room for first byte right away
+                    if (quadByteCount >= 4) {
+                        if (quadLength >= quadArray.length) {
+                            _quadBuffer = quadArray = growArrayBy(quadArray, quadArray.length);
+                        }
+                        quadArray[quadLength++] = activeQuad;
+                        activeQuad = 0;
+                        quadByteCount = 0;
+                    }
+                    if (charCode < 0x800) { // 2-byte
+                        activeQuad = (activeQuad << 8) | (0xc0 | (charCode >> 6));
+                        ++quadByteCount;
+                        // Second byte gets output below:
+                    } else { // 3 bytes; no need to worry about surrogates here
+                        activeQuad = (activeQuad << 8) | (0xe0 | (charCode >> 12));
+                        ++quadByteCount;
+                        // need room for middle byte?
+                        if (quadByteCount >= 4) {
+                            if (quadLength >= quadArray.length) {
+                                _quadBuffer = quadArray = growArrayBy(quadArray, quadArray.length);
+                            }
+                            quadArray[quadLength++] = activeQuad;
+                            activeQuad = 0;
+                            quadByteCount = 0;
+                        }
+                        activeQuad = (activeQuad << 8) | (0x80 | ((charCode >> 6) & 0x3f));
+                        ++quadByteCount;
+                    }
+                    // And same last byte in both cases, gets output below:
+                    charCode = 0x80 | (charCode & 0x3f);
+                }
+            }
+            // Ok, we have one more byte to add at any rate:
+            if (quadByteCount < 4) {
+                ++quadByteCount;
+                activeQuad = (activeQuad << 8) | charCode;
+            } else {
+                if (quadLength >= quadArray.length) {
+                    _quadBuffer = quadArray = growArrayBy(quadArray, quadArray.length);
+                }
+                quadArray[quadLength++] = activeQuad;
+                activeQuad = charCode;
+                quadByteCount = 1;
+            }
+            charCode = _inputData.readUnsignedByte();
+        }
+
+        if (quadByteCount > 0) {
+            if (quadLength >= quadArray.length) {
+                _quadBuffer = quadArray = growArrayBy(quadArray, quadArray.length);
+            }
+            quadArray[quadLength++] = signExtend(activeQuad, quadByteCount);
+        }
+        String fieldName = _symbols.findName(quadArray, quadLength);
+        if (fieldName == null) {
+            fieldName = addNameFromUtf8(quadArray, quadLength, quadByteCount);
+        }
+        return fieldName;
+    }private final JsonToken _nextTokenOutsideObject(int idx) throws IOException
+    {
+        if (idx == INT_QUOTE) {
+            _tokenIncomplete = true;
+            return (_currToken = JsonToken.VALUE_STRING);
+        }
+        switch (idx) {
+        case '[':
+            _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+            return (_currToken = JsonToken.START_ARRAY);
+        case '{':
+            _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+            return (_currToken = JsonToken.START_OBJECT);
+        case 't':
+            _matchJsonToken("true", 1);
+            return (_currToken = JsonToken.VALUE_TRUE);
+        case 'f':
+            _matchJsonToken("false", 1);
+            return (_currToken = JsonToken.VALUE_FALSE);
+        case 'n':
+            _matchJsonToken("null", 1);
+            return (_currToken = JsonToken.VALUE_NULL);
+        case '-':
+            return (_currToken = _parseNegativeNumber());
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
+            return (_currToken = _parsePositiveNumber(idx));
+        }
+        return (_currToken = _handleInvalidValue(idx));
+    }private final int _nextNonWhitespaceByte() throws IOException
+    {
+        int idx = _nextByte;
+        if (idx < 0) {
+            idx = _inputData.readUnsignedByte();
+        } else {
+            _nextByte = -1;
+        }
+        while (true) {
+            if (idx > INT_SPACE) {
+                if (idx == INT_SLASH || idx == INT_HASH) {
+                    return _skipWhitespaceAndComments(idx);
+                }
+                return idx;
+            } else {
+                // 06-May-2016, tatu: Could verify validity of WS, but for now why bother.
+                //   ... but line number is useful thingy
+                if (idx == INT_CR || idx == INT_LF) {
+                    ++_currInputRow;
+                }
+            }
+            idx = _inputData.readUnsignedByte();
+        }
+    }private final JsonToken _nextAfterFieldName()
+    {
+        _nameCopied = false; // need to invalidate if it was copied
+        JsonToken token = _nextToken;
+        _nextToken = null;
+
+        // Also: may need to start new context?
+        if (token == JsonToken.START_ARRAY) {
+            _parsingContext = _parsingContext.createChildArrayContext(_tokenInputRow, _tokenInputCol);
+        } else if (token == JsonToken.START_OBJECT) {
+            _parsingContext = _parsingContext.createChildObjectContext(_tokenInputRow, _tokenInputCol);
+        }
+        return (_currToken = token);
+    }protected final void _matchJsonToken(String expectedToken, int idx) throws IOException
+    {
+        final int length = expectedToken.length();
+        do {
+            int charCode = _inputData.readUnsignedByte();
+            if (charCode != expectedToken.charAt(idx)) {
+                _reportUnexpectedToken(charCode, expectedToken.substring(0, idx));
+            }
+        } while (++idx < length);
+
+        int charCode = _inputData.readUnsignedByte();
+        if (charCode >= '0' && charCode != ']' && charCode != '}') { // expected/allowed chars
+            _verifyMatchEnd(expectedToken, idx, charCode);
+        }
+        _nextByte = charCode;
+    } /**
+     * Method called when we see non-white space character other
+     * than double quote, when expecting a field name.
+     * In standard mode will just throw an exception; but
+     * in non-standard modes may be able to parse name.
+     */
+    protected String _handleUnquotedName(int charCode) throws IOException
+    {
+        if (charCode == '\'' && isEnabled(Feature.ALLOW_SINGLE_QUOTES)) {
+            return _parseApostropheName();
+        }
+        if (!isEnabled(Feature.ALLOW_UNQUOTED_FIELD_NAMES)) {
+            char currChar = (char) _decodeUtf8CharForError(charCode);
+            _reportUnexpectedChar(currChar, "was expecting double-quote to start field name");
+        }
+        /* Also: note that although we use a different table here,
+         * it does NOT handle UTF-8 decoding. It'll just pass those
+         * high-bit codes as acceptable for later decoding.
+         */
+        final int[] codePoints = CharTypes.getInputCodeUtf8JsNames();
+        // Also: must start with a valid character...
+        if (codePoints[charCode] != 0) {
+            _reportUnexpectedChar(charCode, "was expecting either valid name character (for unquoted name) or double-quote (for quoted) to start field name");
+        }
+
+        /* Ok, now; instead of ultra-optimizing parsing here (as with
+         * regular JSON names), let's just use the generic "slow"
+         * variant. Can measure its impact later on if need be
+         */
+        int[] quadArray = _quadBuffer;
+        int quadLength = 0;
+        int activeQuad = 0;
+        int quadByteCount = 0;
+
+        while (true) {
+            // Ok, we have one more byte to add at any rate:
+            if (quadByteCount < 4) {
+                ++quadByteCount;
+                activeQuad = (activeQuad << 8) | charCode;
+            } else {
+                if (quadLength >= quadArray.length) {
+                    _quadBuffer = quadArray = growArrayBy(quadArray, quadArray.length);
+                }
+                quadArray[quadLength++] = activeQuad;
+                activeQuad = charCode;
+                quadByteCount = 1;
+            }
+            charCode = _inputData.readUnsignedByte();
+            if (codePoints[charCode] != 0) {
+                break;
+            }
+        }
+        // Note: we must "push back" character read here for future consumption
+        _nextByte = charCode;
+        if (quadByteCount > 0) {
+            if (quadLength >= quadArray.length) {
+                _quadBuffer = quadArray = growArrayBy(quadArray, quadArray.length);
+            }
+            quadArray[quadLength++] = activeQuad;
+        }
+        String fieldName = _symbols.findName(quadArray, quadLength);
+        if (fieldName == null) {
+            fieldName = addNameFromUtf8(quadArray, quadLength, quadByteCount);
+        }
+        return fieldName;
+    } /**
+     * Method for handling cases where first non-space character
+     * of an expected value token is not legal for standard JSON content.
+     */
+    protected JsonToken _handleInvalidValue(int currChar)
+        throws IOException
+    {
+        // Most likely an error, unless we are to allow single-quote-strings
+        switch (currChar) {
+        case ']':
+            if (!_parsingContext.inArray()) {
+                break;
+            }
+            // fall through
+        case ',':
+            /* !!! TODO: 08-May-2016, tatu: To support `Feature.ALLOW_MISSING_VALUES` would
+             *    need handling here...
+             */
+            if (isEnabled(Feature.ALLOW_MISSING_VALUES)) {
+//               _inputPtr--;
+                _nextByte = currChar;
+               return JsonToken.VALUE_NULL;
+            }
+            // fall through
+        case '}':
+            // Error: neither is valid at this point; valid closers have
+            // been handled earlier
+            _reportUnexpectedChar(currChar, "expected a value");
+        case '\'':
+            if (isEnabled(Feature.ALLOW_SINGLE_QUOTES)) {
+                return _finishAposString();
+            }
+            break;
+        case 'N':
+            _matchJsonToken("NaN", 1);
+            if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
+                return resetAsNaN("NaN", Double.NaN);
+            }
+            _reportError("Non-standard token 'NaN': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
+            break;
+        case 'I':
+            _matchJsonToken("Infinity", 1);
+            if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
+                return resetAsNaN("Infinity", Double.POSITIVE_INFINITY);
+            }
+            _reportError("Non-standard token 'Infinity': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
+            break;
+        case '+': // note: '-' is taken as number
+            return _handleInvalidNumberTokenStart(_inputData.readUnsignedByte(), false);
+        }
+        // [core#77] Try to decode most likely token
+        if (Character.isJavaIdentifierStart(currChar)) {
+            _reportUnexpectedToken(currChar, ""+((char) currChar), "('true', 'false' or 'null')");
+        }
+        // but if it doesn't look like a token:
+        _reportUnexpectedChar(currChar, "expected a valid value (number, String, array, object, 'true', 'false' or 'null')");
+        return null;
+    } /**
+     * Method called if expected numeric value (due to leading sign) does not
+     * look like a number
+     */
+    protected JsonToken _handleInvalidNumberTokenStart(int charCode, boolean isNegative)
+        throws IOException
+    {
+        while (charCode == 'I') {
+            charCode = _inputData.readUnsignedByte();
+            String matchedToken;
+            if (charCode == 'N') {
+                matchedToken = isNegative ? "-INF" :"+INF";
+            } else if (charCode == 'n') {
+                matchedToken = isNegative ? "-Infinity" :"+Infinity";
+            } else {
+                break;
+            }
+            _matchJsonToken(matchedToken, 3);
+            if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
+                return resetAsNaN(matchedToken, isNegative ? Double.NEGATIVE_INFINITY : Double.POSITIVE_INFINITY);
+            }
+            _reportError("Non-standard token '"+ matchedToken +"': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
+        }
+        reportUnexpectedNumberChar(charCode, "expected digit (0-9) to follow minus sign, for valid numeric value");
+        return null;
+    }protected final String _getText(JsonToken token)
+    {
+        if (token == null) {
+            return null;
+        }
+        switch (token.id()) {
+        case ID_FIELD_NAME:
+            return _parsingContext.getCurrentName();
+
+        case ID_STRING:
+            // fall through
+        case ID_NUMBER_INT:
+        case ID_NUMBER_FLOAT:
+            return _textBuffer.contentsAsString();
+        default:
+        	return token.asString();
+        }
+    }private final void _finishStringUtf8(char[] charBuffer, int charIndex, int currChar)
+        throws IOException
+    {
+        // Here we do want to do full decoding, hence:
+        final int[] codePoints = UTF8_CHAR_CLASS_TABLE;
+        int outputEnd = charBuffer.length;
+
+        main_loop:
+        for (;; currChar = _inputData.readUnsignedByte()) {
+            // Then the tight ASCII non-funny-char loop:
+            while (codePoints[currChar] == 0) {
+                if (charIndex >= outputEnd) {
+                    charBuffer = _textBuffer.finishCurrentSegment();
+                    charIndex = 0;
+                    outputEnd = charBuffer.length;
+                }
+                charBuffer[charIndex++] = (char) currChar;
+                currChar = _inputData.readUnsignedByte();
+            }
+            // Ok: end marker, escape or multi-byte?
+            if (currChar == INT_QUOTE) {
+                break main_loop;
+            }
+            switch (codePoints[currChar]) {
+            case 1: // backslash
+                currChar = _decodeEscaped();
+                break;
+            case 2: // 2-byte UTF
+                currChar = decodeUtf8_2Bytes(currChar);
+                break;
+            case 3: // 3-byte UTF
+                currChar = decodeUtf8_3(currChar);
+                break;
+            case 4: // 4-byte UTF
+                currChar = decodeUtf8_4(currChar);
+                // Let's add first part right away:
+                charBuffer[charIndex++] = (char) (0xD800 | (currChar >> 10));
+                if (charIndex >= charBuffer.length) {
+                    charBuffer = _textBuffer.finishCurrentSegment();
+                    charIndex = 0;
+                    outputEnd = charBuffer.length;
+                }
+                currChar = 0xDC00 | (currChar & 0x3FF);
+                // And let the other char output down below
+                break;
+            default:
+                if (currChar < INT_SPACE) {
+                    _throwUnquotedSpace(currChar, "string value");
+                } else {
+                    // Is this good enough error message?
+                    _reportInvalidCharacter(currChar);
+                }
+            }
+            // Need more room?
+            if (charIndex >= charBuffer.length) {
+                charBuffer = _textBuffer.finishCurrentSegment();
+                charIndex = 0;
+                outputEnd = charBuffer.length;
+            }
+            // Ok, let's add char to output:
+            charBuffer[charIndex++] = (char) currChar;
+        }
+        _textBuffer.setCurrentLength(charIndex);
+    }@Override
+    protected void _finishString() throws IOException
+    {
+        int outPointer = 0;
+        char[] outBuffer = _textBuffer.emptyAndGetCurrentSegment();
+        final int[] codePoints = UTF8_CHAR_CLASS_TABLE;
+        final int outputEnd = outBuffer.length;
+
+        do {
+            int mapper = _inputData.readUnsignedByte();
+            if (codePoints[mapper] != 0) {
+                if (mapper == INT_QUOTE) {
+                    _textBuffer.setCurrentLength(outPointer);
+                    return;
+                }
+                _finishStringUtf8(outBuffer, outPointer, mapper);
+                return;
+            }
+            outBuffer[outPointer++] = (char) mapper;
+        } while (outPointer < outputEnd);
+        _finishStringUtf8(outBuffer, outPointer, _inputData.readUnsignedByte());
+    }protected JsonToken _finishAposString() throws IOException
+    {
+        int currChar = 0;
+        // Otherwise almost verbatim copy of _finishString()
+        int charIndex = 0;
+        char[] charBuffer = _textBuffer.emptyAndGetCurrentSegment();
+
+        // Here we do want to do full decoding, hence:
+        final int[] codePoints = UTF8_CHAR_CLASS_TABLE;
+
+        main_loop:
+        while (true) {
+            // Then the tight ascii non-funny-char loop:
+            ascii_loop:
+            while (true) {
+                int outputEnd = charBuffer.length;
+                if (charIndex >= charBuffer.length) {
+                    charBuffer = _textBuffer.finishCurrentSegment();
+                    charIndex = 0;
+                    outputEnd = charBuffer.length;
+                }
+                do {
+                    currChar = _inputData.readUnsignedByte();
+                    if (currChar == '\'') {
+                        break main_loop;
+                    }
+                    if (codePoints[currChar] != 0) {
+                        break ascii_loop;
+                    }
+                    charBuffer[charIndex++] = (char) currChar;
+                } while (charIndex < outputEnd);
+            }
+            switch (codePoints[currChar]) {
+            case 1: // backslash
+                currChar = _decodeEscaped();
+                break;
+            case 2: // 2-byte UTF
+                currChar = decodeUtf8_2Bytes(currChar);
+                break;
+            case 3: // 3-byte UTF
+                currChar = decodeUtf8_3(currChar);
+                break;
+            case 4: // 4-byte UTF
+                currChar = decodeUtf8_4(currChar);
+                // Let's add first part right away:
+                charBuffer[charIndex++] = (char) (0xD800 | (currChar >> 10));
+                if (charIndex >= charBuffer.length) {
+                    charBuffer = _textBuffer.finishCurrentSegment();
+                    charIndex = 0;
+                }
+                currChar = 0xDC00 | (currChar & 0x3FF);
+                // And let the other char output down below
+                break;
+            default:
+                if (currChar < INT_SPACE) {
+                    _throwUnquotedSpace(currChar, "string value");
+                }
+                // Is this good enough error message?
+                _reportInvalidCharacter(currChar);
+            }
+            // Need more room?
+            if (charIndex >= charBuffer.length) {
+                charBuffer = _textBuffer.finishCurrentSegment();
+                charIndex = 0;
+            }
+            // Ok, let's add char to output:
+            charBuffer[charIndex++] = (char) currChar;
+        }
+        _textBuffer.setCurrentLength(charIndex);
+
+        return JsonToken.VALUE_STRING;
+    }private String _finishAndGetString() throws IOException
+    {
+        int charIndex = 0;
+        char[] charBuffer = _textBuffer.emptyAndGetCurrentSegment();
+        final int[] codePoints = UTF8_CHAR_CLASS_TABLE;
+        final int outputEnd = charBuffer.length;
+
+        do {
+            int currChar = _inputData.readUnsignedByte();
+            if (codePoints[currChar] != 0) {
+                if (currChar == INT_QUOTE) {
+                    return _textBuffer.setCurrentAndReturn(charIndex);
+                }
+                _finishStringUtf8(charBuffer, charIndex, currChar);
+                return _textBuffer.contentsAsString();
+            }
+            charBuffer[charIndex++] = (char) currChar;
+        } while (charIndex < outputEnd);
+        _finishStringUtf8(charBuffer, charIndex, _inputData.readUnsignedByte());
+        return _textBuffer.contentsAsString();
+    }protected int _decodeUtf8CharForError(int leadByte) throws IOException
+    {
+        int currChar = leadByte & 0xFF;
+        if (currChar > 0x7F) { // if >= 0, is ascii and fine as is
+            int requiredSize;
+
+            // Ok; if we end here, we got multi-byte combination
+            if ((currChar & 0xE0) == 0xC0) { // 2 bytes (0x0080 - 0x07FF)
+                currChar &= 0x1F;
+                requiredSize = 1;
+            } else if ((currChar & 0xF0) == 0xE0) { // 3 bytes (0x0800 - 0xFFFF)
+                currChar &= 0x0F;
+                requiredSize = 2;
+            } else if ((currChar & 0xF8) == 0xF0) {
+                // 4 bytes; double-char with surrogates and all...
+                currChar &= 0x07;
+                requiredSize = 3;
+            } else {
+                _reportInvalidInitialByte(currChar & 0xFF);
+                requiredSize = 1; // never gets here
+            }
+
+            int continuationByte = _inputData.readUnsignedByte();
+            if ((continuationByte & 0xC0) != 0x080) {
+                _reportInvalidMiddleByte(continuationByte & 0xFF);
+            }
+            currChar = (currChar << 6) | (continuationByte & 0x3F);
+
+            if (requiredSize > 1) { // needed == 1 means 2 bytes total
+                continuationByte = _inputData.readUnsignedByte(); // 3rd byte
+                if ((continuationByte & 0xC0) != 0x080) {
+                    _reportInvalidMiddleByte(continuationByte & 0xFF);
+                }
+                currChar = (currChar << 6) | (continuationByte & 0x3F);
+                if (requiredSize > 2) { // 4 bytes? (need surrogates)
+                    continuationByte = _inputData.readUnsignedByte();
+                    if ((continuationByte & 0xC0) != 0x080) {
+                        _reportInvalidMiddleByte(continuationByte & 0xFF);
+                    }
+                    currChar = (currChar << 6) | (continuationByte & 0x3F);
+                }
+            }
+        }
+        return currChar;
+    }@Override
+    protected char _decodeEscaped() throws IOException
+    {
+        int mapper = _inputData.readUnsignedByte();
+
+        switch (mapper) {
+            // First, ones that are mapped
+        case 'b':
+            return '\b';
+        case 't':
+            return '\t';
+        case 'n':
+            return '\n';
+        case 'f':
+            return '\f';
+        case 'r':
+            return '\r';
+
+            // And these are to be returned as they are
+        case '"':
+        case '/':
+        case '\\':
+            return (char) mapper;
+
+        case 'u': // and finally hex-escaped
+            break;
+
+        default:
+            return _handleUnrecognizedCharacterEscape((char) _decodeUtf8CharForError(mapper));
+        }
+
+        // Ok, a hex escape. Need 4 characters
+        int decodedInt = 0;
+        for (int idx = 0; idx < 4; ++idx) {
+            int chars = _inputData.readUnsignedByte();
+            int hexNibble = CharTypes.charToHex(chars);
+            if (hexNibble < 0) {
+                _reportUnexpectedChar(chars, "expected a hex-digit for character escape sequence");
+            }
+            decodedInt = (decodedInt << 4) | hexNibble;
+        }
+        return (char) decodedInt;
+    } /**
+     * Efficient handling for incremental parsing of base64-encoded
+     * textual content.
+     */
+    @SuppressWarnings("resource")
+    protected final byte[] _decodeBase64ToBytes(Base64Variant base64Variant) throws IOException
+    {
+        ByteArrayBuilder byteAccumulator = _getByteArrayBuilder();
+
+        //main_loop:
+        while (true) {
+            // first, we'll skip preceding white space, if any
+            int charCode;
+            do {
+                charCode = _inputData.readUnsignedByte();
+            } while (charCode <= INT_SPACE);
+            int bitCount = base64Variant.decodeBase64Char(charCode);
+            if (bitCount < 0) { // reached the end, fair and square?
+                if (charCode == INT_QUOTE) {
+                    return byteAccumulator.toByteArray();
+                }
+                bitCount = _decodeBase64Escape(base64Variant, charCode, 0);
+                if (bitCount < 0) { // white space to skip
+                    continue;
+                }
+            }
+            int decodedValue = bitCount;
+
+            // then second base64 char; can't get padding yet, nor ws
+            charCode = _inputData.readUnsignedByte();
+            bitCount = base64Variant.decodeBase64Char(charCode);
+            if (bitCount < 0) {
+                bitCount = _decodeBase64Escape(base64Variant, charCode, 1);
+            }
+            decodedValue = (decodedValue << 6) | bitCount;
+            // third base64 char; can be padding, but not ws
+            charCode = _inputData.readUnsignedByte();
+            bitCount = base64Variant.decodeBase64Char(charCode);
+
+            // First branch: can get padding (-> 1 byte)
+            if (bitCount < 0) {
+                if (bitCount != Base64Variant.BASE64_VALUE_PADDING) {
+                    // could also just be 'missing'  padding
+                    if (charCode == '"' && !base64Variant.usesPadding()) {
+                        decodedValue >>= 4;
+                        byteAccumulator.append(decodedValue);
+                        return byteAccumulator.toByteArray();
+                    }
+                    bitCount = _decodeBase64Escape(base64Variant, charCode, 2);
+                }
+                if (bitCount == Base64Variant.BASE64_VALUE_PADDING) {
+                    charCode = _inputData.readUnsignedByte();
+                    if (!base64Variant.usesPaddingChar(charCode)) {
+                        throw reportInvalidBase64Char(base64Variant, charCode, 3, "expected padding character '"+ base64Variant.getPaddingChar()+"'");
+                    }
+                    // Got 12 bits, only need 8, need to shift
+                    decodedValue >>= 4;
+                    byteAccumulator.append(decodedValue);
+                    continue;
+                }
+            }
+            // Nope, 2 or 3 bytes
+            decodedValue = (decodedValue << 6) | bitCount;
+            // fourth and last base64 char; can be padding, but not ws
+            charCode = _inputData.readUnsignedByte();
+            bitCount = base64Variant.decodeBase64Char(charCode);
+            if (bitCount < 0) {
+                if (bitCount != Base64Variant.BASE64_VALUE_PADDING) {
+                    // could also just be 'missing'  padding
+                    if (charCode == '"' && !base64Variant.usesPadding()) {
+                        decodedValue >>= 2;
+                        byteAccumulator.appendTwoBytes(decodedValue);
+                        return byteAccumulator.toByteArray();
+                    }
+                    bitCount = _decodeBase64Escape(base64Variant, charCode, 3);
+                }
+                if (bitCount == Base64Variant.BASE64_VALUE_PADDING) {
+                    /* With padding we only get 2 bytes; but we have
+                     * to shift it a bit so it is identical to triplet
+                     * case with partial output.
+                     * 3 chars gives 3x6 == 18 bits, of which 2 are
+                     * dummies, need to discard:
+                     */
+                    decodedValue >>= 2;
+                    byteAccumulator.appendTwoBytes(decodedValue);
+                    continue;
+                }
+            }
+            // otherwise, our triplet is now complete
+            decodedValue = (decodedValue << 6) | bitCount;
+            byteAccumulator.appendThreeBytes(decodedValue);
+        }
+    }private final int _consumeColon() throws IOException
+    {
+        int idx = _nextByte;
+        if (idx < 0) {
+            idx = _inputData.readUnsignedByte();
+        } else {
+            _nextByte = -1;
+        }
+        // Fast path: colon with optional single-space/tab before and/or after:
+        if (idx == INT_COLON) { // common case, no leading space
+            idx = _inputData.readUnsignedByte();
+            if (idx > INT_SPACE) { // nor trailing
+                if (idx == INT_SLASH || idx == INT_HASH) {
+                    return _skipColon(idx, true);
+                }
+                return idx;
+            }
+            if (idx == INT_SPACE || idx == INT_TAB) {
+                idx = _inputData.readUnsignedByte();
+                if (idx > INT_SPACE) {
+                    if (idx == INT_SLASH || idx == INT_HASH) {
+                        return _skipColon(idx, true);
+                    }
+                    return idx;
+                }
+            }
+            return _skipColon(idx, true); // true -> skipped colon
+        }
+        if (idx == INT_SPACE || idx == INT_TAB) {
+            idx = _inputData.readUnsignedByte();
+        }
+        if (idx == INT_COLON) {
+            idx = _inputData.readUnsignedByte();
+            if (idx > INT_SPACE) {
+                if (idx == INT_SLASH || idx == INT_HASH) {
+                    return _skipColon(idx, true);
+                }
+                return idx;
+            }
+            if (idx == INT_SPACE || idx == INT_TAB) {
+                idx = _inputData.readUnsignedByte();
+                if (idx > INT_SPACE) {
+                    if (idx == INT_SLASH || idx == INT_HASH) {
+                        return _skipColon(idx, true);
+                    }
+                    return idx;
+                }
+            }
+            return _skipColon(idx, true);
+        }
+        return _skipColon(idx, false);
+    }@Override
+    protected void _closeInput() throws IOException { }private void _closeCurrentScope(int idx) throws JsonParseException {
+        if (idx == INT_RBRACKET) {
+            if (!_parsingContext.inArray()) {
+                _reportMismatchedEndMarker(idx, '}');
+            }
+            _parsingContext = _parsingContext.clearAndGetParent();
+            _currToken = JsonToken.END_ARRAY;
+        }
+        if (idx == INT_RCURLY) {
+            if (!_parsingContext.inObject()) {
+                _reportMismatchedEndMarker(idx, ']');
+            }
+            _parsingContext = _parsingContext.clearAndGetParent();
+            _currToken = JsonToken.END_OBJECT;
+        }
+    }public UTF8JsonInputParser(IOContext ioContext, int parserFeatures, DataInput dataInputStream,
+                               ObjectCodec mapper, ByteQuadsCanonicalizer symbolTable,
+                               int initialByte)
+    {
+        super(ioContext, parserFeatures);
+        _objectCodec = mapper;
+        _symbols = symbolTable;
+        _inputData = dataInputStream;
+        _nextByte = initialByte;
+    }}
diff --git a/src/test/java/com/fasterxml/jackson/core/TestVersions.java b/src/test/java/com/fasterxml/jackson/core/TestVersions.java
index 865be6f1..ac959ae5 100644
--- a/src/test/java/com/fasterxml/jackson/core/TestVersions.java
+++ b/src/test/java/com/fasterxml/jackson/core/TestVersions.java
@@ -2,6 +2,7 @@ package com.fasterxml.jackson.core;
 
 import com.fasterxml.jackson.core.json.*;
 import com.fasterxml.jackson.core.io.IOContext;
+import com.fasterxml.jackson.core.json.parsers.JsonParserFromReader;
 import com.fasterxml.jackson.core.sym.CharsToNameCanonicalizer;
 import com.fasterxml.jackson.core.util.BufferRecycler;
 
@@ -13,7 +14,7 @@ public class TestVersions extends com.fasterxml.jackson.core.BaseTest
     public void testCoreVersions() throws Exception
     {
         assertVersion(new JsonFactory().version());
-        ReaderBasedJsonParser jp = new ReaderBasedJsonParser(getIOContext(), 0, null, null,
+        JsonParserFromReader jp = new JsonParserFromReader(getIOContext(), 0, null, null,
                 CharsToNameCanonicalizer.createRoot());
         assertVersion(jp.version());
         jp.close();
diff --git a/src/test/java/com/fasterxml/jackson/core/read/TrailingCommasTest.java b/src/test/java/com/fasterxml/jackson/core/read/TrailingCommasTest.java
index 5ca9eb38..9e169207 100644
--- a/src/test/java/com/fasterxml/jackson/core/read/TrailingCommasTest.java
+++ b/src/test/java/com/fasterxml/jackson/core/read/TrailingCommasTest.java
@@ -5,7 +5,7 @@ import com.fasterxml.jackson.core.JsonFactory;
 import com.fasterxml.jackson.core.JsonParser;
 import com.fasterxml.jackson.core.JsonParser.Feature;
 import com.fasterxml.jackson.core.JsonToken;
-import com.fasterxml.jackson.core.json.UTF8DataInputJsonParser;
+import com.fasterxml.jackson.core.json.parsers.UTF8JsonInputParser;
 
 import org.junit.Test;
 import org.junit.runner.RunWith;
@@ -311,7 +311,7 @@ public class TrailingCommasTest extends BaseTest {
 
   private void assertEnd(JsonParser p) throws IOException {
     // Issue #325
-    if (!(p instanceof UTF8DataInputJsonParser)) {
+    if (!(p instanceof UTF8JsonInputParser)) {
       JsonToken next = p.nextToken();
       assertNull("expected end of stream but found " + next, next);
     }
diff --git a/src/test/java/com/fasterxml/jackson/core/sym/SymbolTableMergingTest.java b/src/test/java/com/fasterxml/jackson/core/sym/SymbolTableMergingTest.java
index 766fada9..0cb6a815 100644
--- a/src/test/java/com/fasterxml/jackson/core/sym/SymbolTableMergingTest.java
+++ b/src/test/java/com/fasterxml/jackson/core/sym/SymbolTableMergingTest.java
@@ -3,7 +3,7 @@ package com.fasterxml.jackson.core.sym;
 import java.io.IOException;
 
 import com.fasterxml.jackson.core.*;
-import com.fasterxml.jackson.core.json.ReaderBasedJsonParser;
+import com.fasterxml.jackson.core.json.parsers.JsonParserFromReader;
 import com.fasterxml.jackson.core.json.UTF8StreamJsonParser;
 
 /**
@@ -106,7 +106,7 @@ public class SymbolTableMergingTest
             assertEquals(0, f.byteSymbolCount());
         } else {
             jp = f.createParser(doc);
-            assertEquals(ReaderBasedJsonParser.class, jp.getClass());
+            assertEquals(JsonParserFromReader.class, jp.getClass());
             assertEquals(0, f.charSymbolCount());
         }
         return jp;

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

file="/home/jackson-core/pom.xml"
old_version="2.15.0-rc2-SNAPSHOT"
new_version="2.15.5-SNAPSHOT"
sed -i "s/$old_version/$new_version/g" "$file"

mvn clean test -Dmaven.test.skip=false -DfailIfNoTests=false || true
