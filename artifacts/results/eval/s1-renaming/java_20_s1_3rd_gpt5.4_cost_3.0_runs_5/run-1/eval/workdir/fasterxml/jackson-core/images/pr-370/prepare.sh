#!/bin/bash
set -e

cd /home/jackson-core
git reset --hard
bash /home/check_git_changes.sh
git checkout f42556388bb8ad547a55e4ee7cfb52a99f670186

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/com/fasterxml/jackson/core/JsonFactory.java b/src/main/java/com/fasterxml/jackson/core/JsonFactory.java
index 2e33185a..2402f2cb 100644
--- a/src/main/java/com/fasterxml/jackson/core/JsonFactory.java
+++ b/src/main/java/com/fasterxml/jackson/core/JsonFactory.java
@@ -1287,7 +1287,7 @@ public class JsonFactory
      * @since 2.1
      */
     protected JsonParser _createParser(Reader r, IOContext ctxt) throws IOException {
-        return new ReaderBasedJsonParser(ctxt, _parserFeatures, r, _objectCodec,
+        return new ReaderBackedJsonParser(ctxt, _parserFeatures, r, _objectCodec,
                 _rootCharSymbols.makeChild(_factoryFeatures));
     }
 
@@ -1299,7 +1299,7 @@ public class JsonFactory
      */
     protected JsonParser _createParser(char[] data, int offset, int len, IOContext ctxt,
             boolean recyclable) throws IOException {
-        return new ReaderBasedJsonParser(ctxt, _parserFeatures, null, _objectCodec,
+        return new ReaderBackedJsonParser(ctxt, _parserFeatures, null, _objectCodec,
                 _rootCharSymbols.makeChild(_factoryFeatures),
                         data, offset, offset+len, recyclable);
     }
@@ -1337,7 +1337,7 @@ public class JsonFactory
         // at least handle possible UTF-8 BOM
         int firstByte = ByteSourceJsonBootstrapper.skipUTF8BOM(input);
         ByteQuadsCanonicalizer can = _byteSymbolCanonicalizer.makeChild(_factoryFeatures);
-        return new UTF8DataInputJsonParser(ctxt, _parserFeatures, input,
+        return new UTF8InputStreamJsonParser(ctxt, _parserFeatures, input,
                 _objectCodec, can, firstByte);
     }
 
diff --git a/src/main/java/com/fasterxml/jackson/core/json/ByteSourceJsonBootstrapper.java b/src/main/java/com/fasterxml/jackson/core/json/ByteSourceJsonBootstrapper.java
index 6ff84e9c..30cb7b93 100644
--- a/src/main/java/com/fasterxml/jackson/core/json/ByteSourceJsonBootstrapper.java
+++ b/src/main/java/com/fasterxml/jackson/core/json/ByteSourceJsonBootstrapper.java
@@ -255,7 +255,7 @@ public final class ByteSourceJsonBootstrapper
                         _inputBuffer, _inputPtr, _inputEnd, _bufferRecyclable);
             }
         }
-        return new ReaderBasedJsonParser(_context, parserFeatures, constructReader(), codec,
+        return new ReaderBackedJsonParser(_context, parserFeatures, constructReader(), codec,
                 rootCharSymbols.makeChild(factoryFeatures));
     }
 
diff --git a/src/main/java/com/fasterxml/jackson/core/json/ReaderBackedJsonParser.java b/src/main/java/com/fasterxml/jackson/core/json/ReaderBackedJsonParser.java
new file mode 100644
index 00000000..c0faa714
--- /dev/null
+++ b/src/main/java/com/fasterxml/jackson/core/json/ReaderBackedJsonParser.java
@@ -0,0 +1,2854 @@
+package com.fasterxml.jackson.core.json;
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
+public class ReaderBackedJsonParser // final in 2.3, earlier
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
+    /**
+     * Method called when caller wants to provide input buffer directly,
+     * and it may or may not be recyclable use standard recycle context.
+     *
+     * @since 2.4
+     */
+    public ReaderBackedJsonParser(IOContext ioContext, int configFlags, Reader reader,
+                                  ObjectCodec serializationHandler, CharsToNameCanonicalizer symbolTable,
+                                  char[] charArray, int beginIndex, int finishPos,
+                                  boolean isRecyclable)
+    {
+        super(ioContext, configFlags);
+        _reader = reader;
+        _inputBuffer = charArray;
+        _inputPtr = beginIndex;
+        _inputEnd = finishPos;
+        _objectCodec = serializationHandler;
+        _symbols = symbolTable;
+        _hashSeed = symbolTable.hashSeed();
+        _bufferRecyclable = isRecyclable;
+    }
+
+    /**
+     * Method called when input comes as a {@link java.io.Reader}, and buffer allocation
+     * can be done using default mechanism.
+     */
+    public ReaderBackedJsonParser(IOContext ioContext, int configFlags, Reader reader,
+                                  ObjectCodec serializationHandler, CharsToNameCanonicalizer symbolTable)
+    {
+        super(ioContext, configFlags);
+        _reader = reader;
+        _inputBuffer = ioContext.allocTokenBuffer();
+        _inputPtr = 0;
+        _inputEnd = 0;
+        _objectCodec = serializationHandler;
+        _symbols = symbolTable;
+        _hashSeed = symbolTable.hashSeed();
+        _bufferRecyclable = true;
+    }
+
+    /*
+    /**********************************************************
+    /* Base method defs, overrides
+    /**********************************************************
+     */
+
+    @Override public ObjectCodec getCodec() { return _objectCodec; }
+    @Override public void setCodec(ObjectCodec handler) { _objectCodec = handler; }
+
+    @Override
+    public int releaseBuffer(Writer writerOut) throws IOException {
+        int numChars = _inputEnd - _inputPtr;
+        if (numChars < 1) { return 0; }
+        // let's just advance ptr to end
+        int initialPointer = _inputPtr;
+        writerOut.write(_inputBuffer, initialPointer, numChars);
+        return numChars;
+    }
+
+    @Override public Object getInputSource() { return _reader; }
+
+    @Deprecated // since 2.8
+    protected char getNextChar(String endOfStreamMessage) throws IOException {
+        return getNextChar(endOfStreamMessage, null);
+    }
+    
+    protected char getNextChar(String endOfStreamMessage, JsonToken expectedToken) throws IOException {
+        if (_inputPtr >= _inputEnd) {
+            if (!_refillBuffer()) {
+                _reportInvalidEOF(endOfStreamMessage, expectedToken);
+            }
+        }
+        return _inputBuffer[_inputPtr++];
+    }
+
+    @Override
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
+    }
+
+    /**
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
+            char[] buffer = _inputBuffer;
+            if (buffer != null) {
+                _inputBuffer = null;
+                _ioContext.releaseTokenBuffer(buffer);
+            }
+        }
+    }
+
+    /*
+    /**********************************************************
+    /* Low-level access, supporting
+    /**********************************************************
+     */
+
+    protected void _ensureLoadMore() throws IOException {
+        if (!_refillBuffer()) { _reportInvalidEOF(); }
+    }
+    
+    protected boolean _refillBuffer() throws IOException
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
+    }
+
+    /*
+    /**********************************************************
+    /* Public API, data access
+    /**********************************************************
+     */
+
+    /**
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
+    }
+
+    @Override // since 2.8
+    public int getText(Writer output) throws IOException
+    {
+        JsonToken token = _currToken;
+        if (token == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                _finishString(); // only strings can be incomplete
+            }
+            return _textBuffer.contentsToWriter(output);
+        }
+        if (token == JsonToken.FIELD_NAME) {
+            String nameStr = _parsingContext.getCurrentName();
+            output.write(nameStr);
+            return nameStr.length();
+        }
+        if (token != null) {
+            if (token.isNumeric()) {
+                return _textBuffer.contentsToWriter(output);
+            }
+            char[] chars = token.asCharArray();
+            output.write(chars);
+            return chars.length;
+        }
+        return 0;
+    }
+    
+    // // // Let's override default impls for improved performance
+
+    // @since 2.1
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
+    }
+
+    // @since 2.1
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
+    }
+
+    protected final String _getText(JsonToken token) {
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
+    }
+
+    @Override
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
+    }
+
+    @Override
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
+    }
+
+    @Override
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
+    }
+
+    @Override
+    public byte[] getBinaryValue(Base64Variant base64Type) throws IOException
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
+                _binaryValue = _decodeBase64ToByteArray(base64Type);
+            } catch (IllegalArgumentException illegalArgumentEx) {
+                throw _constructError("Failed to decode VALUE_STRING as base64 ("+ base64Type +"): "+ illegalArgumentEx.getMessage());
+            }
+            /* let's clear incomplete only now; allows for accessing other
+             * textual content in error cases
+             */
+            _tokenIncomplete = false;
+        } else { // may actually require conversion...
+            if (_binaryValue == null) {
+                @SuppressWarnings("resource")
+                ByteArrayBuilder byteAccumulator = _getByteArrayBuilder();
+                _decodeBase64(getText(), byteAccumulator, base64Type);
+                _binaryValue = byteAccumulator.toByteArray();
+            }
+        }
+        return _binaryValue;
+    }
+
+    @Override
+    public int readBinaryValueInto(Base64Variant base64Type, OutputStream outputStream) throws IOException
+    {
+        // if we have already read the token, just use whatever we may have
+        if (!_tokenIncomplete || _currToken != JsonToken.VALUE_STRING) {
+            byte[] bytes = getBinaryValue(base64Type);
+            outputStream.write(bytes);
+            return bytes.length;
+        }
+        // otherwise do "real" incremental parsing...
+        byte[] buffer = _ioContext.allocBase64Buffer();
+        try {
+            return _readBinaryValue(base64Type, outputStream, buffer);
+        } finally {
+            _ioContext.releaseBase64Buffer(buffer);
+        }
+    }
+
+    protected int _readBinaryValue(Base64Variant base64Type, OutputStream outputStream, byte[] dataArray) throws IOException
+    {
+        int outIndex = 0;
+        final int outputLimit = dataArray.length - 3;
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
+            int bitMask = base64Type.decodeBase64Char(chars);
+            if (bitMask < 0) { // reached the end, fair and square?
+                if (chars == '"') {
+                    break;
+                }
+                bitMask = _decodeBase64Escape(base64Type, chars, 0);
+                if (bitMask < 0) { // white space to skip
+                    continue;
+                }
+            }
+
+            // enough room? If not, flush
+            if (outIndex > outputLimit) {
+                bytesWritten += outIndex;
+                outputStream.write(dataArray, 0, outIndex);
+                outIndex = 0;
+            }
+
+            int decodedValue = bitMask;
+
+            // then second base64 char; can't get padding yet, nor ws
+
+            if (_inputPtr >= _inputEnd) {
+                _ensureLoadMore();
+            }
+            chars = _inputBuffer[_inputPtr++];
+            bitMask = base64Type.decodeBase64Char(chars);
+            if (bitMask < 0) {
+                bitMask = _decodeBase64Escape(base64Type, chars, 1);
+            }
+            decodedValue = (decodedValue << 6) | bitMask;
+
+            // third base64 char; can be padding, but not ws
+            if (_inputPtr >= _inputEnd) {
+                _ensureLoadMore();
+            }
+            chars = _inputBuffer[_inputPtr++];
+            bitMask = base64Type.decodeBase64Char(chars);
+
+            // First branch: can get padding (-> 1 byte)
+            if (bitMask < 0) {
+                if (bitMask != Base64Variant.BASE64_VALUE_PADDING) {
+                    // as per [JACKSON-631], could also just be 'missing'  padding
+                    if (chars == '"' && !base64Type.usesPadding()) {
+                        decodedValue >>= 4;
+                        dataArray[outIndex++] = (byte) decodedValue;
+                        break;
+                    }
+                    bitMask = _decodeBase64Escape(base64Type, chars, 2);
+                }
+                if (bitMask == Base64Variant.BASE64_VALUE_PADDING) {
+                    // Ok, must get padding
+                    if (_inputPtr >= _inputEnd) {
+                        _ensureLoadMore();
+                    }
+                    chars = _inputBuffer[_inputPtr++];
+                    if (!base64Type.usesPaddingChar(chars)) {
+                        throw reportInvalidBase64Char(base64Type, chars, 3, "expected padding character '"+ base64Type.getPaddingChar()+"'");
+                    }
+                    // Got 12 bits, only need 8, need to shift
+                    decodedValue >>= 4;
+                    dataArray[outIndex++] = (byte) decodedValue;
+                    continue;
+                }
+            }
+            // Nope, 2 or 3 bytes
+            decodedValue = (decodedValue << 6) | bitMask;
+            // fourth and last base64 char; can be padding, but not ws
+            if (_inputPtr >= _inputEnd) {
+                _ensureLoadMore();
+            }
+            chars = _inputBuffer[_inputPtr++];
+            bitMask = base64Type.decodeBase64Char(chars);
+            if (bitMask < 0) {
+                if (bitMask != Base64Variant.BASE64_VALUE_PADDING) {
+                    // as per [JACKSON-631], could also just be 'missing'  padding
+                    if (chars == '"' && !base64Type.usesPadding()) {
+                        decodedValue >>= 2;
+                        dataArray[outIndex++] = (byte) (decodedValue >> 8);
+                        dataArray[outIndex++] = (byte) decodedValue;
+                        break;
+                    }
+                    bitMask = _decodeBase64Escape(base64Type, chars, 3);
+                }
+                if (bitMask == Base64Variant.BASE64_VALUE_PADDING) {
+                    /* With padding we only get 2 bytes; but we have
+                     * to shift it a bit so it is identical to triplet
+                     * case with partial output.
+                     * 3 chars gives 3x6 == 18 bits, of which 2 are
+                     * dummies, need to discard:
+                     */
+                    decodedValue >>= 2;
+                    dataArray[outIndex++] = (byte) (decodedValue >> 8);
+                    dataArray[outIndex++] = (byte) decodedValue;
+                    continue;
+                }
+            }
+            // otherwise, our triplet is now complete
+            decodedValue = (decodedValue << 6) | bitMask;
+            dataArray[outIndex++] = (byte) (decodedValue >> 16);
+            dataArray[outIndex++] = (byte) (decodedValue >> 8);
+            dataArray[outIndex++] = (byte) decodedValue;
+        }
+        _tokenIncomplete = false;
+        if (outIndex > 0) {
+            bytesWritten += outIndex;
+            outputStream.write(dataArray, 0, outIndex);
+        }
+        return bytesWritten;
+    }
+
+    /*
+    /**********************************************************
+    /* Public API, traversal
+    /**********************************************************
+     */
+
+    /**
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
+            _skipQuotedString(); // only strings can be partial
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
+            _endScope(index);
+            return _currToken;
+        }
+
+        // Nope: do we then expect a comma?
+        if (_parsingContext.expectComma()) {
+            index = _skipCommaAndWhitespace(index);
+
+            // Was that a trailing comma?
+            if ((_features & FEAT_MASK_TRAILING_COMMA) != 0) {
+                if ((index == INT_RBRACKET) || (index == INT_RCURLY)) {
+                    _endScope(index);
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
+            _updateNameStartLocation();
+            String fieldName = (index == INT_QUOTE) ? _parseFieldName() : _handleUnquotedName(index);
+            _parsingContext.setCurrentName(fieldName);
+            _currToken = JsonToken.FIELD_NAME;
+            index = _skipOptionalColon();
+        }
+        updateLocation();
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
+            _matchTrueToken();
+            token = JsonToken.VALUE_TRUE;
+            break;
+        case 'f':
+            _matchFalseToken();
+            token = JsonToken.VALUE_FALSE;
+            break;
+        case 'n':
+            _matchNullLiteral();
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
+    }
+
+    private final JsonToken _nextTokenAfterName()
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
+    }
+
+    @Override
+    public void completeToken() throws IOException {
+        if (_tokenIncomplete) {
+            _tokenIncomplete = false;
+            _finishString(); // only strings can be incomplete
+        }
+    }
+
+    /*
+    /**********************************************************
+    /* Public API, nextXxx() overrides
+    /**********************************************************
+     */
+
+    // Implemented since 2.7
+    @Override
+    public boolean nextPropertyName(SerializableString serializableStringValue) throws IOException
+    {
+        // // // Note: most of code below is copied from nextToken()
+
+        _numTypesValid = NR_UNKNOWN;
+        if (_currToken == JsonToken.FIELD_NAME) {
+            _nextTokenAfterName();
+            return false;
+        }
+        if (_tokenIncomplete) {
+            _skipQuotedString();
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
+            _endScope(index);
+            return false;
+        }
+
+        if (_parsingContext.expectComma()) {
+            index = _skipCommaAndWhitespace(index);
+
+            // Was that a trailing comma?
+            if ((_features & FEAT_MASK_TRAILING_COMMA) != 0) {
+                if ((index == INT_RBRACKET) || (index == INT_RCURLY)) {
+                    _endScope(index);
+                    return false;
+                }
+            }
+        }
+
+        if (!_parsingContext.inObject()) {
+            updateLocation();
+            _nextTokenOutsideObject(index);
+            return false;
+        }
+
+        _updateNameStartLocation();
+        if (index == INT_QUOTE) {
+            // when doing literal match, must consider escaping:
+            char[] propChars = serializableStringValue.asQuotedChars();
+            final int count = propChars.length;
+
+            // Require 4 more bytes for faster skipping of colon that follows name
+            if ((_inputPtr + count + 4) < _inputEnd) { // maybe...
+                // first check length match by
+                final int finishPos = _inputPtr+ count;
+                if (_inputBuffer[finishPos] == '"') {
+                    int startOffset = 0;
+                    int pointer = _inputPtr;
+                    while (true) {
+                        if (pointer == finishPos) { // yes, match!
+                            _parsingContext.setCurrentName(serializableStringValue.getValue());
+                            _parseNextTokenForNameYes(_skipColonFastPath(pointer +1));
+                            return true;
+                        }
+                        if (propChars[startOffset] != _inputBuffer[pointer]) {
+                            break;
+                        }
+                        ++startOffset;
+                        ++pointer;
+                    }
+                }
+            }
+        }
+        return _isNextFieldNameMaybe(index, serializableStringValue.getValue());
+    }
+
+    @Override
+    public String nextPropertyName() throws IOException
+    {
+        // // // Note: this is almost a verbatim copy of nextToken() (minus comments)
+
+        _numTypesValid = NR_UNKNOWN;
+        if (_currToken == JsonToken.FIELD_NAME) {
+            _nextTokenAfterName();
+            return null;
+        }
+        if (_tokenIncomplete) {
+            _skipQuotedString();
+        }
+        int index = _skipWhitespaceOrEnd();
+        if (index < 0) {
+            close();
+            _currToken = null;
+            return null;
+        }
+        _binaryValue = null;
+        if (index == INT_RBRACKET) {
+            updateLocation();
+            if (!_parsingContext.inArray()) {
+                _reportMismatchedEndMarker(index, '}');
+            }
+            _parsingContext = _parsingContext.clearAndGetParent();
+            _currToken = JsonToken.END_ARRAY;
+            return null;
+        }
+        if (index == INT_RCURLY) {
+            updateLocation();
+            if (!_parsingContext.inObject()) {
+                _reportMismatchedEndMarker(index, ']');
+            }
+            _parsingContext = _parsingContext.clearAndGetParent();
+            _currToken = JsonToken.END_OBJECT;
+            return null;
+        }
+        if (_parsingContext.expectComma()) {
+            index = _skipCommaAndWhitespace(index);
+        }
+        if (!_parsingContext.inObject()) {
+            updateLocation();
+            _nextTokenOutsideObject(index);
+            return null;
+        }
+
+        _updateNameStartLocation();
+        String fieldName = (index == INT_QUOTE) ? _parseFieldName() : _handleUnquotedName(index);
+        _parsingContext.setCurrentName(fieldName);
+        _currToken = JsonToken.FIELD_NAME;
+        index = _skipOptionalColon();
+
+        updateLocation();
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
+            _matchFalseToken();
+            token = JsonToken.VALUE_FALSE;
+            break;
+        case 'n':
+            _matchNullLiteral();
+            token = JsonToken.VALUE_NULL;
+            break;
+        case 't':
+            _matchTrueToken();
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
+    }
+
+    private final void _parseNextTokenForNameYes(int index) throws IOException
+    {
+        _currToken = JsonToken.FIELD_NAME;
+        updateLocation();
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
+            _matchTokenExact("true", 1);
+            _nextToken = JsonToken.VALUE_TRUE;
+            return;
+        case 'f':
+            _matchTokenExact("false", 1);
+            _nextToken = JsonToken.VALUE_FALSE;
+            return;
+        case 'n':
+            _matchTokenExact("null", 1);
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
+    }
+
+    protected boolean _isNextFieldNameMaybe(int index, String matchTarget) throws IOException
+    {
+        // // // and this is back to standard nextToken()
+        String fieldName = (index == INT_QUOTE) ? _parseFieldName() : _handleUnquotedName(index);
+        _parsingContext.setCurrentName(fieldName);
+        _currToken = JsonToken.FIELD_NAME;
+        index = _skipOptionalColon();
+        updateLocation();
+        if (index == INT_QUOTE) {
+            _tokenIncomplete = true;
+            _nextToken = JsonToken.VALUE_STRING;
+            return matchTarget.equals(fieldName);
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
+            _matchFalseToken();
+            token = JsonToken.VALUE_FALSE;
+            break;
+        case 'n':
+            _matchNullLiteral();
+            token = JsonToken.VALUE_NULL;
+            break;
+        case 't':
+            _matchTrueToken();
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
+        return matchTarget.equals(fieldName);
+    }
+
+    private final JsonToken _nextTokenOutsideObject(int index) throws IOException
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
+            _matchTokenExact("true", 1);
+            return (_currToken = JsonToken.VALUE_TRUE);
+        case 'f':
+            _matchTokenExact("false", 1);
+            return (_currToken = JsonToken.VALUE_FALSE);
+        case 'n':
+            _matchTokenExact("null", 1);
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
+    }
+
+    // note: identical to one in UTF8StreamJsonParser
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
+    }
+
+    // note: identical to one in Utf8StreamParser
+    @Override
+    public final int nextIntValueOrDefault(int fallback) throws IOException
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
+            return fallback;
+        }
+        // !!! TODO: optimize this case as well
+        return (nextJsonToken() == JsonToken.VALUE_NUMBER_INT) ? getIntValue() : fallback;
+    }
+
+    // note: identical to one in Utf8StreamParser
+    @Override
+    public final long nextLongValueOrDefault(long fallback) throws IOException
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
+            return fallback;
+        }
+        // !!! TODO: optimize this case as well
+        return (nextJsonToken() == JsonToken.VALUE_NUMBER_INT) ? getLongValue() : fallback;
+    }
+
+    // note: identical to one in UTF8StreamJsonParser
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
+            int index = token.id();
+            if (index == ID_TRUE) return Boolean.TRUE;
+            if (index == ID_FALSE) return Boolean.FALSE;
+        }
+        return null;
+    }
+
+    /*
+    /**********************************************************
+    /* Internal methods, number parsing
+    /**********************************************************
+     */
+
+    /**
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
+        int startIndex = pointer -1; // to include digit already read
+        final int inputSize = _inputEnd;
+
+        // One special case, leading zero(es):
+        if (chars == INT_0) {
+            return _parseNumber(false, startIndex);
+        }
+
+        /* First, let's see if the whole number is contained within
+         * the input buffer unsplit. This should be the common case;
+         * and to simplify processing, we will just reparse contents
+         * in the alternative case (number split on buffer boundary)
+         */
+
+        int intCount = 1; // already got one
+
+        // First let's get the obligatory integer part:
+        int_loop:
+        while (true) {
+            if (pointer >= inputSize) {
+                _inputPtr = startIndex;
+                return _parseNumber(false, startIndex);
+            }
+            chars = (int) _inputBuffer[pointer++];
+            if (chars < INT_0 || chars > INT_9) {
+                break int_loop;
+            }
+            ++intCount;
+        }
+        if (chars == INT_PERIOD || chars == INT_e || chars == INT_E) {
+            _inputPtr = pointer;
+            return _parseFloatingPoint(chars, startIndex, pointer, false, intCount);
+        }
+        // Got it all: let's add to text buffer for parsing, access
+        --pointer; // need to push back following separator
+        _inputPtr = pointer;
+        // As per #105, need separating space between root values; check here
+        if (_parsingContext.inRoot()) {
+            _verifyRootWhitespace(chars);
+        }
+        int count = pointer - startIndex;
+        _textBuffer.resetWithShared(_inputBuffer, startIndex, count);
+        return resetInt(false, intCount);
+    }
+
+    private final JsonToken _parseFloatingPoint(int chars, int startIndex, int pointer, boolean isNegative, int intCount)
+        throws IOException
+    {
+        final int inputSize = _inputEnd;
+        int fractionDigits = 0;
+
+        // And then see if we get other parts
+        if (chars == '.') { // yes, fraction
+            fract_loop:
+            while (true) {
+                if (pointer >= inputSize) {
+                    return _parseNumber(isNegative, startIndex);
+                }
+                chars = (int) _inputBuffer[pointer++];
+                if (chars < INT_0 || chars > INT_9) {
+                    break fract_loop;
+                }
+                ++fractionDigits;
+            }
+            // must be followed by sequence of ints, one minimum
+            if (fractionDigits == 0) {
+                reportUnexpectedNumberChar(chars, "Decimal point not followed by a digit");
+            }
+        }
+        int exponentDigits = 0;
+        if (chars == 'e' || chars == 'E') { // and/or exponent
+            if (pointer >= inputSize) {
+                _inputPtr = startIndex;
+                return _parseNumber(isNegative, startIndex);
+            }
+            // Sign indicator?
+            chars = (int) _inputBuffer[pointer++];
+            if (chars == INT_MINUS || chars == INT_PLUS) { // yup, skip for now
+                if (pointer >= inputSize) {
+                    _inputPtr = startIndex;
+                    return _parseNumber(isNegative, startIndex);
+                }
+                chars = (int) _inputBuffer[pointer++];
+            }
+            while (chars <= INT_9 && chars >= INT_0) {
+                ++exponentDigits;
+                if (pointer >= inputSize) {
+                    _inputPtr = startIndex;
+                    return _parseNumber(isNegative, startIndex);
+                }
+                chars = (int) _inputBuffer[pointer++];
+            }
+            // must be followed by sequence of ints, one minimum
+            if (exponentDigits == 0) {
+                reportUnexpectedNumberChar(chars, "Exponent indicator not followed by a digit");
+            }
+        }
+        --pointer; // need to push back following separator
+        _inputPtr = pointer;
+        // As per #105, need separating space between root values; check here
+        if (_parsingContext.inRoot()) {
+            _verifyRootWhitespace(chars);
+        }
+        int count = pointer - startIndex;
+        _textBuffer.resetWithShared(_inputBuffer, startIndex, count);
+        // And there we have it!
+        return resetFloat(isNegative, intCount, fractionDigits, exponentDigits);
+    }
+
+    protected final JsonToken _parseNegativeNumber() throws IOException
+    {
+        int pointer = _inputPtr;
+        int startIndex = pointer -1; // to include sign/digit already read
+        final int inputSize = _inputEnd;
+
+        if (pointer >= inputSize) {
+            return _parseNumber(true, startIndex);
+        }
+        int chars = _inputBuffer[pointer++];
+        // First check: must have a digit to follow minus sign
+        if (chars > INT_9 || chars < INT_0) {
+            _inputPtr = pointer;
+            return _handleInvalidNumericStart(chars, true);
+        }
+        // One special case, leading zero(es):
+        if (chars == INT_0) {
+            return _parseNumber(true, startIndex);
+        }
+        int intCount = 1; // already got one
+
+        // First let's get the obligatory integer part:
+        int_loop:
+        while (true) {
+            if (pointer >= inputSize) {
+                return _parseNumber(true, startIndex);
+            }
+            chars = (int) _inputBuffer[pointer++];
+            if (chars < INT_0 || chars > INT_9) {
+                break int_loop;
+            }
+            ++intCount;
+        }
+
+        if (chars == INT_PERIOD || chars == INT_e || chars == INT_E) {
+            _inputPtr = pointer;
+            return _parseFloatingPoint(chars, startIndex, pointer, true, intCount);
+        }
+        --pointer;
+        _inputPtr = pointer;
+        if (_parsingContext.inRoot()) {
+            _verifyRootWhitespace(chars);
+        }
+        int count = pointer - startIndex;
+        _textBuffer.resetWithShared(_inputBuffer, startIndex, count);
+        return resetInt(true, intCount);
+    }
+
+    /**
+     * Method called to parse a number, when the primary parse
+     * method has failed to parse it, due to it being split on
+     * buffer boundary. As a result code is very similar, except
+     * that it has to explicitly copy contents to the text buffer
+     * instead of just sharing the main input buffer.
+     */
+    private final JsonToken _parseNumber(boolean isNegative, int startIndex) throws IOException
+    {
+        _inputPtr = isNegative ? (startIndex +1) : startIndex;
+        char[] outputBuffer = _textBuffer.emptyAndGetCurrentSegment();
+        int outIndex = 0;
+
+        // Need to prepend sign?
+        if (isNegative) {
+            outputBuffer[outIndex++] = '-';
+        }
+
+        // This is the place to do leading-zero check(s) too:
+        int intCount = 0;
+        char handler = (_inputPtr < _inputEnd) ? _inputBuffer[_inputPtr++]
+                : getNextChar("No digit following minus sign", JsonToken.VALUE_NUMBER_INT);
+        if (handler == '0') {
+            handler = _verifyNoLeadingZeros();
+        }
+        boolean endOfFile = false;
+
+        // Ok, first the obligatory integer part:
+        int_loop:
+        while (handler >= '0' && handler <= '9') {
+            ++intCount;
+            if (outIndex >= outputBuffer.length) {
+                outputBuffer = _textBuffer.finishCurrentSegment();
+                outIndex = 0;
+            }
+            outputBuffer[outIndex++] = handler;
+            if (_inputPtr >= _inputEnd && !_refillBuffer()) {
+                // EOF is legal for main level int values
+                handler = CHAR_NULL;
+                endOfFile = true;
+                break int_loop;
+            }
+            handler = _inputBuffer[_inputPtr++];
+        }
+        // Also, integer part is not optional
+        if (intCount == 0) {
+            return _handleInvalidNumericStart(handler, isNegative);
+        }
+
+        int fractionDigits = 0;
+        // And then see if we get other parts
+        if (handler == '.') { // yes, fraction
+            if (outIndex >= outputBuffer.length) {
+                outputBuffer = _textBuffer.finishCurrentSegment();
+                outIndex = 0;
+            }
+            outputBuffer[outIndex++] = handler;
+
+            fract_loop:
+            while (true) {
+                if (_inputPtr >= _inputEnd && !_refillBuffer()) {
+                    endOfFile = true;
+                    break fract_loop;
+                }
+                handler = _inputBuffer[_inputPtr++];
+                if (handler < INT_0 || handler > INT_9) {
+                    break fract_loop;
+                }
+                ++fractionDigits;
+                if (outIndex >= outputBuffer.length) {
+                    outputBuffer = _textBuffer.finishCurrentSegment();
+                    outIndex = 0;
+                }
+                outputBuffer[outIndex++] = handler;
+            }
+            // must be followed by sequence of ints, one minimum
+            if (fractionDigits == 0) {
+                reportUnexpectedNumberChar(handler, "Decimal point not followed by a digit");
+            }
+        }
+
+        int exponentDigits = 0;
+        if (handler == 'e' || handler == 'E') { // exponent?
+            if (outIndex >= outputBuffer.length) {
+                outputBuffer = _textBuffer.finishCurrentSegment();
+                outIndex = 0;
+            }
+            outputBuffer[outIndex++] = handler;
+            // Not optional, can require that we get one more char
+            handler = (_inputPtr < _inputEnd) ? _inputBuffer[_inputPtr++]
+                : getNextChar("expected a digit for number exponent");
+            // Sign indicator?
+            if (handler == '-' || handler == '+') {
+                if (outIndex >= outputBuffer.length) {
+                    outputBuffer = _textBuffer.finishCurrentSegment();
+                    outIndex = 0;
+                }
+                outputBuffer[outIndex++] = handler;
+                // Likewise, non optional:
+                handler = (_inputPtr < _inputEnd) ? _inputBuffer[_inputPtr++]
+                    : getNextChar("expected a digit for number exponent");
+            }
+
+            exp_loop:
+            while (handler <= INT_9 && handler >= INT_0) {
+                ++exponentDigits;
+                if (outIndex >= outputBuffer.length) {
+                    outputBuffer = _textBuffer.finishCurrentSegment();
+                    outIndex = 0;
+                }
+                outputBuffer[outIndex++] = handler;
+                if (_inputPtr >= _inputEnd && !_refillBuffer()) {
+                    endOfFile = true;
+                    break exp_loop;
+                }
+                handler = _inputBuffer[_inputPtr++];
+            }
+            // must be followed by sequence of ints, one minimum
+            if (exponentDigits == 0) {
+                reportUnexpectedNumberChar(handler, "Exponent indicator not followed by a digit");
+            }
+        }
+
+        // Ok; unless we hit end-of-input, need to push last char read back
+        if (!endOfFile) {
+            --_inputPtr;
+            if (_parsingContext.inRoot()) {
+                _verifyRootWhitespace(handler);
+            }
+        }
+        _textBuffer.setCurrentLength(outIndex);
+        // And there we have it!
+        return reset(isNegative, intCount, fractionDigits, exponentDigits);
+    }
+
+    /**
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
+        return _verifyLeadingZeros();
+    }
+
+    private char _verifyLeadingZeros() throws IOException
+    {
+        if (_inputPtr >= _inputEnd && !_refillBuffer()) {
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
+            while (_inputPtr < _inputEnd || _refillBuffer()) {
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
+    }
+
+    /**
+     * Method called if expected numeric value (due to leading sign) does not
+     * look like a number
+     */
+    protected JsonToken _handleInvalidNumericStart(int chars, boolean isNegative) throws IOException
+    {
+        if (chars == 'I') {
+            if (_inputPtr >= _inputEnd) {
+                if (!_refillBuffer()) {
+                    _reportInvalidEOFInValue(JsonToken.VALUE_NUMBER_INT);
+                }
+            }
+            chars = _inputBuffer[_inputPtr++];
+            if (chars == 'N') {
+                String matchText = isNegative ? "-INF" :"+INF";
+                _matchTokenExact(matchText, 3);
+                if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
+                    return resetAsNaN(matchText, isNegative ? Double.NEGATIVE_INFINITY : Double.POSITIVE_INFINITY);
+                }
+                _reportError("Non-standard token '"+ matchText +"': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
+            } else if (chars == 'n') {
+                String matchText = isNegative ? "-Infinity" :"+Infinity";
+                _matchTokenExact(matchText, 3);
+                if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
+                    return resetAsNaN(matchText, isNegative ? Double.NEGATIVE_INFINITY : Double.POSITIVE_INFINITY);
+                }
+                _reportError("Non-standard token '"+ matchText +"': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
+            }
+        }
+        reportUnexpectedNumberChar(chars, "expected digit (0-9) to follow minus sign, for valid numeric value");
+        return null;
+    }
+
+    /**
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
+            _skipCRLF();
+            return;
+        case '\n':
+            ++_currInputRow;
+            _currInputRowStart = _inputPtr;
+            return;
+        }
+        _reportMissingRootWS(chars);
+    }
+
+    /*
+    /**********************************************************
+    /* Internal methods, secondary parsing
+    /**********************************************************
+     */
+
+    protected final String _parseFieldName() throws IOException
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
+        return _parseFieldName(beginIndex, nameHash, INT_QUOTE);
+    }
+
+    private String _parseFieldName(int startIndex, int nameHash, int terminator) throws IOException
+    {
+        _textBuffer.resetWithShared(_inputBuffer, startIndex, (_inputPtr - startIndex));
+
+        /* Output pointers; calls will also ensure that the buffer is
+         * not shared and has room for at least one more char.
+         */
+        char[] outputBuffer = _textBuffer.getCurrentSegment();
+        int outIndex = _textBuffer.getCurrentSegmentSize();
+
+        while (true) {
+            if (_inputPtr >= _inputEnd) {
+                if (!_refillBuffer()) {
+                    _reportInvalidEOF(" in field name", JsonToken.FIELD_NAME);
+                }
+            }
+            char handler = _inputBuffer[_inputPtr++];
+            int index = (int) handler;
+            if (index <= INT_BACKSLASH) {
+                if (index == INT_BACKSLASH) {
+                    /* Although chars outside of BMP are to be escaped as
+                     * an UTF-16 surrogate pair, does that affect decoding?
+                     * For now let's assume it does not.
+                     */
+                    handler = _decodeEscaped();
+                } else if (index <= terminator) {
+                    if (index == terminator) {
+                        break;
+                    }
+                    if (index < INT_SPACE) {
+                        _throwUnquotedSpace(index, "name");
+                    }
+                }
+            }
+            nameHash = (nameHash * CharsToNameCanonicalizer.HASH_MULT) + handler;
+            // Ok, let's add char to output:
+            outputBuffer[outIndex++] = handler;
+
+            // Need more room?
+            if (outIndex >= outputBuffer.length) {
+                outputBuffer = _textBuffer.finishCurrentSegment();
+                outIndex = 0;
+            }
+        }
+        _textBuffer.setCurrentLength(outIndex);
+        {
+            TextBuffer textBuffer = _textBuffer;
+            char[] buffer = textBuffer.getTextBuffer();
+            int beginIndex = textBuffer.getTextOffset();
+            int count = textBuffer.size();
+            return _symbols.findSymbol(buffer, beginIndex, count, nameHash);
+        }
+    }
+
+    /**
+     * Method called when we see non-white space character other
+     * than double quote, when expecting a field name.
+     * In standard mode will just throw an expection; but
+     * in non-standard modes may be able to parse name.
+     */
+    protected String _handleUnquotedName(int index) throws IOException
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
+        final int highestCode = charCodes.length;
+
+        // Also: first char must be a valid name char, but NOT be number
+        boolean firstCharValid;
+
+        if (index < highestCode) { // identifier, or a number ([Issue#102])
+            firstCharValid = (charCodes[index] == 0);
+        } else {
+            firstCharValid = Character.isJavaIdentifierPart((char) index);
+        }
+        if (!firstCharValid) {
+            _reportUnexpectedChar(index, "was expecting either valid name character (for unquoted name) or double-quote (for quoted) to start field name");
+        }
+        int pointer = _inputPtr;
+        int nameHash = _hashSeed;
+        final int inputSize = _inputEnd;
+
+        if (pointer < inputSize) {
+            do {
+                int chars = _inputBuffer[pointer];
+                if (chars < highestCode) {
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
+            } while (pointer < inputSize);
+        }
+        int beginIndex = _inputPtr-1;
+        _inputPtr = pointer;
+        return _handleOddName(beginIndex, nameHash, charCodes);
+    }
+
+    protected String _parseApostropheName() throws IOException
+    {
+        // Note: mostly copy of_parseFieldName
+        int pointer = _inputPtr;
+        int nameHash = _hashSeed;
+        final int inputSize = _inputEnd;
+
+        if (pointer < inputSize) {
+            final int[] charCodes = _icLatin1;
+            final int highestCode = charCodes.length;
+
+            do {
+                int chars = _inputBuffer[pointer];
+                if (chars == '\'') {
+                    int beginIndex = _inputPtr;
+                    _inputPtr = pointer +1; // to skip the quote
+                    return _symbols.findSymbol(_inputBuffer, beginIndex, pointer - beginIndex, nameHash);
+                }
+                if (chars < highestCode && charCodes[chars] != 0) {
+                    break;
+                }
+                nameHash = (nameHash * CharsToNameCanonicalizer.HASH_MULT) + chars;
+                ++pointer;
+            } while (pointer < inputSize);
+        }
+
+        int beginIndex = _inputPtr;
+        _inputPtr = pointer;
+
+        return _parseFieldName(beginIndex, nameHash, '\'');
+    }
+
+    /**
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
+            _matchTokenExact("NaN", 1);
+            if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
+                return resetAsNaN("NaN", Double.NaN);
+            }
+            _reportError("Non-standard token 'NaN': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
+            break;
+        case 'I':
+            _matchTokenExact("Infinity", 1);
+            if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
+                return resetAsNaN("Infinity", Double.POSITIVE_INFINITY);
+            }
+            _reportError("Non-standard token 'Infinity': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
+            break;
+        case '+': // note: '-' is taken as number
+            if (_inputPtr >= _inputEnd) {
+                if (!_refillBuffer()) {
+                    _reportInvalidEOFInValue(JsonToken.VALUE_NUMBER_INT);
+                }
+            }
+            return _handleInvalidNumericStart(_inputBuffer[_inputPtr++], false);
+        }
+        // [core#77] Try to decode most likely token
+        if (Character.isJavaIdentifierStart(index)) {
+            _reportUnexpectedToken(""+((char) index), "('true', 'false' or 'null')");
+        }
+        // but if it doesn't look like a token:
+        _reportUnexpectedChar(index, "expected a valid value (number, String, array, object, 'true', 'false' or 'null')");
+        return null;
+    }
+
+    protected JsonToken _handleApostrophe() throws IOException
+    {
+        char[] outputBuffer = _textBuffer.emptyAndGetCurrentSegment();
+        int outIndex = _textBuffer.getCurrentSegmentSize();
+
+        while (true) {
+            if (_inputPtr >= _inputEnd) {
+                if (!_refillBuffer()) {
+                    _reportInvalidEOF(": was expecting closing quote for a string value",
+                            JsonToken.VALUE_STRING);
+                }
+            }
+            char handler = _inputBuffer[_inputPtr++];
+            int index = (int) handler;
+            if (index <= '\\') {
+                if (index == '\\') {
+                    /* Although chars outside of BMP are to be escaped as
+                     * an UTF-16 surrogate pair, does that affect decoding?
+                     * For now let's assume it does not.
+                     */
+                    handler = _decodeEscaped();
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
+            if (outIndex >= outputBuffer.length) {
+                outputBuffer = _textBuffer.finishCurrentSegment();
+                outIndex = 0;
+            }
+            // Ok, let's add char to output:
+            outputBuffer[outIndex++] = handler;
+        }
+        _textBuffer.setCurrentLength(outIndex);
+        return JsonToken.VALUE_STRING;
+    }
+
+    private String _handleOddName(int startIndex, int nameHash, int[] charCodes) throws IOException
+    {
+        _textBuffer.resetWithShared(_inputBuffer, startIndex, (_inputPtr - startIndex));
+        char[] outputBuffer = _textBuffer.getCurrentSegment();
+        int outIndex = _textBuffer.getCurrentSegmentSize();
+        final int highestCode = charCodes.length;
+
+        while (true) {
+            if (_inputPtr >= _inputEnd) {
+                if (!_refillBuffer()) { // acceptable for now (will error out later)
+                    break;
+                }
+            }
+            char handler = _inputBuffer[_inputPtr];
+            int index = (int) handler;
+            if (index <= highestCode) {
+                if (charCodes[index] != 0) {
+                    break;
+                }
+            } else if (!Character.isJavaIdentifierPart(handler)) {
+                break;
+            }
+            ++_inputPtr;
+            nameHash = (nameHash * CharsToNameCanonicalizer.HASH_MULT) + index;
+            // Ok, let's add char to output:
+            outputBuffer[outIndex++] = handler;
+
+            // Need more room?
+            if (outIndex >= outputBuffer.length) {
+                outputBuffer = _textBuffer.finishCurrentSegment();
+                outIndex = 0;
+            }
+        }
+        _textBuffer.setCurrentLength(outIndex);
+        {
+            TextBuffer textBuffer = _textBuffer;
+            char[] buffer = textBuffer.getTextBuffer();
+            int beginIndex = textBuffer.getTextOffset();
+            int count = textBuffer.size();
+
+            return _symbols.findSymbol(buffer, beginIndex, count, nameHash);
+        }
+    }
+
+    @Override
+    protected final void _finishString() throws IOException
+    {
+        /* First: let's try to see if we have simple String value: one
+         * that does not cross input buffer boundary, and does not
+         * contain escape sequences.
+         */
+        int pointer = _inputPtr;
+        final int inputSize = _inputEnd;
+
+        if (pointer < inputSize) {
+            final int[] charCodes = _icLatin1;
+            final int highestCode = charCodes.length;
+
+            do {
+                int chars = _inputBuffer[pointer];
+                if (chars < highestCode && charCodes[chars] != 0) {
+                    if (chars == '"') {
+                        _textBuffer.resetWithShared(_inputBuffer, _inputPtr, (pointer -_inputPtr));
+                        _inputPtr = pointer +1;
+                        // Yes, we got it all
+                        return;
+                    }
+                    break;
+                }
+                ++pointer;
+            } while (pointer < inputSize);
+        }
+
+        /* Either ran out of input, or bumped into an escape
+         * sequence...
+         */
+        _textBuffer.resetWithCopy(_inputBuffer, _inputPtr, (pointer -_inputPtr));
+        _inputPtr = pointer;
+        _finishQuotedString();
+    }
+
+    protected void _finishQuotedString() throws IOException
+    {
+        char[] outputBuffer = _textBuffer.getCurrentSegment();
+        int outIndex = _textBuffer.getCurrentSegmentSize();
+        final int[] charCodes = _icLatin1;
+        final int highestCode = charCodes.length;
+
+        while (true) {
+            if (_inputPtr >= _inputEnd) {
+                if (!_refillBuffer()) {
+                    _reportInvalidEOF(": was expecting closing quote for a string value",
+                            JsonToken.VALUE_STRING);
+                }
+            }
+            char handler = _inputBuffer[_inputPtr++];
+            int index = (int) handler;
+            if (index < highestCode && charCodes[index] != 0) {
+                if (index == INT_QUOTE) {
+                    break;
+                } else if (index == INT_BACKSLASH) {
+                    /* Although chars outside of BMP are to be escaped as
+                     * an UTF-16 surrogate pair, does that affect decoding?
+                     * For now let's assume it does not.
+                     */
+                    handler = _decodeEscaped();
+                } else if (index < INT_SPACE) {
+                    _throwUnquotedSpace(index, "string value");
+                } // anything else?
+            }
+            // Need more room?
+            if (outIndex >= outputBuffer.length) {
+                outputBuffer = _textBuffer.finishCurrentSegment();
+                outIndex = 0;
+            }
+            // Ok, let's add char to output:
+            outputBuffer[outIndex++] = handler;
+        }
+        _textBuffer.setCurrentLength(outIndex);
+    }
+
+    /**
+     * Method called to skim through rest of unparsed String value,
+     * if it is not needed. This can be done bit faster if contents
+     * need not be stored for future access.
+     */
+    protected final void _skipQuotedString() throws IOException
+    {
+        _tokenIncomplete = false;
+
+        int inputIndex = _inputPtr;
+        int inputLength = _inputEnd;
+        char[] inputBuffer = _inputBuffer;
+
+        while (true) {
+            if (inputIndex >= inputLength) {
+                _inputPtr = inputIndex;
+                if (!_refillBuffer()) {
+                    _reportInvalidEOF(": was expecting closing quote for a string value",
+                            JsonToken.VALUE_STRING);
+                }
+                inputIndex = _inputPtr;
+                inputLength = _inputEnd;
+            }
+            char handler = inputBuffer[inputIndex++];
+            int index = (int) handler;
+            if (index <= INT_BACKSLASH) {
+                if (index == INT_BACKSLASH) {
+                    // Although chars outside of BMP are to be escaped as an UTF-16 surrogate pair,
+                    // does that affect decoding? For now let's assume it does not.
+                    _inputPtr = inputIndex;
+                    /*c = */ _decodeEscaped();
+                    inputIndex = _inputPtr;
+                    inputLength = _inputEnd;
+                } else if (index <= INT_QUOTE) {
+                    if (index == INT_QUOTE) {
+                        _inputPtr = inputIndex;
+                        break;
+                    }
+                    if (index < INT_SPACE) {
+                        _inputPtr = inputIndex;
+                        _throwUnquotedSpace(index, "string value");
+                    }
+                }
+            }
+        }
+    }
+
+    /*
+    /**********************************************************
+    /* Internal methods, other parsing
+    /**********************************************************
+     */
+
+    /**
+     * We actually need to check the character value here
+     * (to see if we have \n following \r).
+     */
+    protected final void _skipCRLF() throws IOException {
+        if (_inputPtr < _inputEnd || _refillBuffer()) {
+            if (_inputBuffer[_inputPtr] == '\n') {
+                ++_inputPtr;
+            }
+        }
+        ++_currInputRow;
+        _currInputRowStart = _inputPtr;
+    }
+
+    private final int _skipOptionalColon() throws IOException
+    {
+        if ((_inputPtr + 4) >= _inputEnd) {
+            return _skipColon(false);
+        }
+        char handler = _inputBuffer[_inputPtr];
+        if (handler == ':') { // common case, no leading space
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
+        if (handler == ' ' || handler == '\t') {
+            handler = _inputBuffer[++_inputPtr];
+        }
+        if (handler == ':') {
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
+    }
+
+    private final int _skipColon(boolean hasColon) throws IOException
+    {
+        while (_inputPtr < _inputEnd || _refillBuffer()) {
+            int index = (int) _inputBuffer[_inputPtr++];
+            if (index > INT_SPACE) {
+                if (index == INT_SLASH) {
+                    skipComment();
+                    continue;
+                }
+                if (index == INT_HASH) {
+                    if (_trySkipYAMLComment()) {
+                        continue;
+                    }
+                }
+                if (hasColon) {
+                    return index;
+                }
+                if (index != INT_COLON) {
+                    _reportUnexpectedChar(index, "was expecting a colon to separate field name and value");
+                }
+                hasColon = true;
+                continue;
+            }
+            if (index < INT_SPACE) {
+                if (index == INT_LF) {
+                    ++_currInputRow;
+                    _currInputRowStart = _inputPtr;
+                } else if (index == INT_CR) {
+                    _skipCRLF();
+                } else if (index != INT_TAB) {
+                    _throwInvalidSpace(index);
+                }
+            }
+        }
+        _reportInvalidEOF(" within/between "+_parsingContext.typeDesc()+" entries",
+                null);
+        return -1;
+    }
+
+    // Variant called when we know there's at least 4 more bytes available
+    private final int _skipColonFastPath(int pointer) throws IOException
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
+        boolean hasColon = (index == INT_COLON);
+        if (hasColon) {
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
+        return _skipColon(hasColon);
+    }
+
+    // Primary loop: no reloading, comment handling
+    private final int _skipCommaAndWhitespace(int index) throws IOException
+    {
+        if (index != INT_COMMA) {
+            _reportUnexpectedChar(index, "was expecting comma to separate "+_parsingContext.typeDesc()+" entries");
+        }
+        while (_inputPtr < _inputEnd) {
+            index = (int) _inputBuffer[_inputPtr++];
+            if (index > INT_SPACE) {
+                if (index == INT_SLASH || index == INT_HASH) {
+                    --_inputPtr;
+                    return _skipAfterComma();
+                }
+                return index;
+            }
+            if (index < INT_SPACE) {
+                if (index == INT_LF) {
+                    ++_currInputRow;
+                    _currInputRowStart = _inputPtr;
+                } else if (index == INT_CR) {
+                    _skipCRLF();
+                } else if (index != INT_TAB) {
+                    _throwInvalidSpace(index);
+                }
+            }
+        }
+        return _skipAfterComma();
+    }
+
+    private final int _skipAfterComma() throws IOException
+    {
+        while (_inputPtr < _inputEnd || _refillBuffer()) {
+            int index = (int) _inputBuffer[_inputPtr++];
+            if (index > INT_SPACE) {
+                if (index == INT_SLASH) {
+                    skipComment();
+                    continue;
+                }
+                if (index == INT_HASH) {
+                    if (_trySkipYAMLComment()) {
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
+                    _skipCRLF();
+                } else if (index != INT_TAB) {
+                    _throwInvalidSpace(index);
+                }
+            }
+        }
+        throw _constructError("Unexpected end-of-input within/between "+_parsingContext.typeDesc()+" entries");
+    }
+
+    private final int _skipWhitespaceOrEnd() throws IOException
+    {
+        // Let's handle first character separately since it is likely that
+        // it is either non-whitespace; or we have longer run of white space
+        if (_inputPtr >= _inputEnd) {
+            if (!_refillBuffer()) {
+                return _eofAsNextChar();
+            }
+        }
+        int index = _inputBuffer[_inputPtr++];
+        if (index > INT_SPACE) {
+            if (index == INT_SLASH || index == INT_HASH) {
+                --_inputPtr;
+                return _skipWhitespaceOrEOF();
+            }
+            return index;
+        }
+        if (index != INT_SPACE) {
+            if (index == INT_LF) {
+                ++_currInputRow;
+                _currInputRowStart = _inputPtr;
+            } else if (index == INT_CR) {
+                _skipCRLF();
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
+                    return _skipWhitespaceOrEOF();
+                }
+                return index;
+            }
+            if (index != INT_SPACE) {
+                if (index == INT_LF) {
+                    ++_currInputRow;
+                    _currInputRowStart = _inputPtr;
+                } else if (index == INT_CR) {
+                    _skipCRLF();
+                } else if (index != INT_TAB) {
+                    _throwInvalidSpace(index);
+                }
+            }
+        }
+        return _skipWhitespaceOrEOF();
+    }
+
+    private int _skipWhitespaceOrEOF() throws IOException
+    {
+        while (true) {
+            if (_inputPtr >= _inputEnd) {
+                if (!_refillBuffer()) { // We ran out of input...
+                    return _eofAsNextChar();
+                }
+            }
+            int index = (int) _inputBuffer[_inputPtr++];
+            if (index > INT_SPACE) {
+                if (index == INT_SLASH) {
+                    skipComment();
+                    continue;
+                }
+                if (index == INT_HASH) {
+                    if (_trySkipYAMLComment()) {
+                        continue;
+                    }
+                }
+                return index;
+            } else if (index != INT_SPACE) {
+                if (index == INT_LF) {
+                    ++_currInputRow;
+                    _currInputRowStart = _inputPtr;
+                } else if (index == INT_CR) {
+                    _skipCRLF();
+                } else if (index != INT_TAB) {
+                    _throwInvalidSpace(index);
+                }
+            }
+        }
+    }
+
+    private void skipComment() throws IOException
+    {
+        if (!isEnabled(Feature.ALLOW_COMMENTS)) {
+            _reportUnexpectedChar('/', "maybe a (non-standard) comment? (not recognized as one since Feature 'ALLOW_COMMENTS' not enabled for parser)");
+        }
+        // First: check which comment (if either) it is:
+        if (_inputPtr >= _inputEnd && !_refillBuffer()) {
+            _reportInvalidEOF(" in a comment", null);
+        }
+        char handler = _inputBuffer[_inputPtr++];
+        if (handler == '/') {
+            _skipToLineEnd();
+        } else if (handler == '*') {
+            _skipCStyleComment();
+        } else {
+            _reportUnexpectedChar(handler, "was expecting either '*' or '/' for a comment");
+        }
+    }
+
+    private void _skipCStyleComment() throws IOException
+    {
+        // Ok: need the matching '*/'
+        while ((_inputPtr < _inputEnd) || _refillBuffer()) {
+            int index = (int) _inputBuffer[_inputPtr++];
+            if (index <= '*') {
+                if (index == '*') { // end?
+                    if ((_inputPtr >= _inputEnd) && !_refillBuffer()) {
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
+                        _skipCRLF();
+                    } else if (index != INT_TAB) {
+                        _throwInvalidSpace(index);
+                    }
+                }
+            }
+        }
+        _reportInvalidEOF(" in a comment", null);
+    }
+
+    private boolean _trySkipYAMLComment() throws IOException
+    {
+        if (!isEnabled(Feature.ALLOW_YAML_COMMENTS)) {
+            return false;
+        }
+        _skipToLineEnd();
+        return true;
+    }
+
+    private void _skipToLineEnd() throws IOException
+    {
+        // Ok: need to find EOF or linefeed
+        while ((_inputPtr < _inputEnd) || _refillBuffer()) {
+            int index = (int) _inputBuffer[_inputPtr++];
+            if (index < INT_SPACE) {
+                if (index == INT_LF) {
+                    ++_currInputRow;
+                    _currInputRowStart = _inputPtr;
+                    break;
+                } else if (index == INT_CR) {
+                    _skipCRLF();
+                    break;
+                } else if (index != INT_TAB) {
+                    _throwInvalidSpace(index);
+                }
+            }
+        }
+    }
+
+    @Override
+    protected char _decodeEscaped() throws IOException
+    {
+        if (_inputPtr >= _inputEnd) {
+            if (!_refillBuffer()) {
+                _reportInvalidEOF(" in character escape sequence", JsonToken.VALUE_STRING);
+            }
+        }
+        char handler = _inputBuffer[_inputPtr++];
+
+        switch ((int) handler) {
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
+            return handler;
+
+        case 'u': // and finally hex-escaped
+            break;
+
+        default:
+            return _handleUnrecognizedCharacterEscape(handler);
+        }
+
+        // Ok, a hex escape. Need 4 characters
+        int decodedInt = 0;
+        for (int index = 0; index < 4; ++index) {
+            if (_inputPtr >= _inputEnd) {
+                if (!_refillBuffer()) {
+                    _reportInvalidEOF(" in character escape sequence", JsonToken.VALUE_STRING);
+                }
+            }
+            int chars = (int) _inputBuffer[_inputPtr++];
+            int numVal = CharTypes.charToHex(chars);
+            if (numVal < 0) {
+                _reportUnexpectedChar(chars, "expected a hex-digit for character escape sequence");
+            }
+            decodedInt = (decodedInt << 4) | numVal;
+        }
+        return (char) decodedInt;
+    }
+
+    private final void _matchTrueToken() throws IOException {
+        int pointer = _inputPtr;
+        if ((pointer + 3) < _inputEnd) {
+            final char[] bytes = _inputBuffer;
+            if (bytes[pointer] == 'r' && bytes[++pointer] == 'u' && bytes[++pointer] == 'e') {
+                char handler = bytes[++pointer];
+                if (handler < '0' || handler == ']' || handler == '}') { // expected/allowed chars
+                    _inputPtr = pointer;
+                    return;
+                }
+            }
+        }
+        // buffer boundary, or problem, offline
+        _matchTokenExact("true", 1);
+    }
+
+    private final void _matchFalseToken() throws IOException {
+        int pointer = _inputPtr;
+        if ((pointer + 4) < _inputEnd) {
+            final char[] bytes = _inputBuffer;
+            if (bytes[pointer] == 'a' && bytes[++pointer] == 'l' && bytes[++pointer] == 's' && bytes[++pointer] == 'e') {
+                char handler = bytes[++pointer];
+                if (handler < '0' || handler == ']' || handler == '}') { // expected/allowed chars
+                    _inputPtr = pointer;
+                    return;
+                }
+            }
+        }
+        // buffer boundary, or problem, offline
+        _matchTokenExact("false", 1);
+    }
+
+    private final void _matchNullLiteral() throws IOException {
+        int pointer = _inputPtr;
+        if ((pointer + 3) < _inputEnd) {
+            final char[] bytes = _inputBuffer;
+            if (bytes[pointer] == 'u' && bytes[++pointer] == 'l' && bytes[++pointer] == 'l') {
+                char handler = bytes[++pointer];
+                if (handler < '0' || handler == ']' || handler == '}') { // expected/allowed chars
+                    _inputPtr = pointer;
+                    return;
+                }
+            }
+        }
+        // buffer boundary, or problem, offline
+        _matchTokenExact("null", 1);
+    }
+
+    /**
+     * Helper method for checking whether input matches expected token
+     */
+    protected final void _matchTokenExact(String expectedToken, int index) throws IOException
+    {
+        final int count = expectedToken.length();
+
+        do {
+            if (_inputPtr >= _inputEnd) {
+                if (!_refillBuffer()) {
+                    _reportUnexpectedToken(expectedToken.substring(0, index));
+                }
+            }
+            if (_inputBuffer[_inputPtr] != expectedToken.charAt(index)) {
+                _reportUnexpectedToken(expectedToken.substring(0, index));
+            }
+            ++_inputPtr;
+        } while (++index < count);
+
+        // but let's also ensure we either get EOF, or non-alphanum char...
+        if (_inputPtr >= _inputEnd) {
+            if (!_refillBuffer()) {
+                return;
+            }
+        }
+        char handler = _inputBuffer[_inputPtr];
+        if (handler < '0' || handler == ']' || handler == '}') { // expected/allowed chars
+            return;
+        }
+        // if Java letter, it's a problem tho
+        if (Character.isJavaIdentifierPart(handler)) {
+            _reportUnexpectedToken(expectedToken.substring(0, index));
+        }
+        return;
+    }
+
+    /*
+    /**********************************************************
+    /* Binary access
+    /**********************************************************
+     */
+
+    /**
+     * Efficient handling for incremental parsing of base64-encoded
+     * textual content.
+     */
+    @SuppressWarnings("resource")
+    protected byte[] _decodeBase64ToByteArray(Base64Variant base64Type) throws IOException
+    {
+        ByteArrayBuilder byteAccumulator = _getByteArrayBuilder();
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
+            int bitMask = base64Type.decodeBase64Char(chars);
+            if (bitMask < 0) {
+                if (chars == '"') { // reached the end, fair and square?
+                    return byteAccumulator.toByteArray();
+                }
+                bitMask = _decodeBase64Escape(base64Type, chars, 0);
+                if (bitMask < 0) { // white space to skip
+                    continue;
+                }
+            }
+            int decodedValue = bitMask;
+
+            // then second base64 char; can't get padding yet, nor ws
+
+            if (_inputPtr >= _inputEnd) {
+                _ensureLoadMore();
+            }
+            chars = _inputBuffer[_inputPtr++];
+            bitMask = base64Type.decodeBase64Char(chars);
+            if (bitMask < 0) {
+                bitMask = _decodeBase64Escape(base64Type, chars, 1);
+            }
+            decodedValue = (decodedValue << 6) | bitMask;
+
+            // third base64 char; can be padding, but not ws
+            if (_inputPtr >= _inputEnd) {
+                _ensureLoadMore();
+            }
+            chars = _inputBuffer[_inputPtr++];
+            bitMask = base64Type.decodeBase64Char(chars);
+
+            // First branch: can get padding (-> 1 byte)
+            if (bitMask < 0) {
+                if (bitMask != Base64Variant.BASE64_VALUE_PADDING) {
+                    // as per [JACKSON-631], could also just be 'missing'  padding
+                    if (chars == '"' && !base64Type.usesPadding()) {
+                        decodedValue >>= 4;
+                        byteAccumulator.append(decodedValue);
+                        return byteAccumulator.toByteArray();
+                    }
+                    bitMask = _decodeBase64Escape(base64Type, chars, 2);
+                }
+                if (bitMask == Base64Variant.BASE64_VALUE_PADDING) {
+                    // Ok, must get more padding chars, then
+                    if (_inputPtr >= _inputEnd) {
+                        _ensureLoadMore();
+                    }
+                    chars = _inputBuffer[_inputPtr++];
+                    if (!base64Type.usesPaddingChar(chars)) {
+                        throw reportInvalidBase64Char(base64Type, chars, 3, "expected padding character '"+ base64Type.getPaddingChar()+"'");
+                    }
+                    // Got 12 bits, only need 8, need to shift
+                    decodedValue >>= 4;
+                    byteAccumulator.append(decodedValue);
+                    continue;
+                }
+                // otherwise we got escaped other char, to be processed below
+            }
+            // Nope, 2 or 3 bytes
+            decodedValue = (decodedValue << 6) | bitMask;
+            // fourth and last base64 char; can be padding, but not ws
+            if (_inputPtr >= _inputEnd) {
+                _ensureLoadMore();
+            }
+            chars = _inputBuffer[_inputPtr++];
+            bitMask = base64Type.decodeBase64Char(chars);
+            if (bitMask < 0) {
+                if (bitMask != Base64Variant.BASE64_VALUE_PADDING) {
+                    // as per [JACKSON-631], could also just be 'missing'  padding
+                    if (chars == '"' && !base64Type.usesPadding()) {
+                        decodedValue >>= 2;
+                        byteAccumulator.appendTwoBytes(decodedValue);
+                        return byteAccumulator.toByteArray();
+                    }
+                    bitMask = _decodeBase64Escape(base64Type, chars, 3);
+                }
+                if (bitMask == Base64Variant.BASE64_VALUE_PADDING) {
+                    // With padding we only get 2 bytes; but we have
+                    // to shift it a bit so it is identical to triplet
+                    // case with partial output.
+                    // 3 chars gives 3x6 == 18 bits, of which 2 are
+                    // dummies, need to discard:
+                    decodedValue >>= 2;
+                    byteAccumulator.appendTwoBytes(decodedValue);
+                    continue;
+                }
+                // otherwise we got escaped other char, to be processed below
+            }
+            // otherwise, our triplet is now complete
+            decodedValue = (decodedValue << 6) | bitMask;
+            byteAccumulator.appendThreeBytes(decodedValue);
+        }
+    }
+
+    /*
+    /**********************************************************
+    /* Internal methods, location updating (refactored in 2.7)
+    /**********************************************************
+     */
+
+    @Override
+    public JsonLocation getTokenLocation()
+    {
+        if (_currToken == JsonToken.FIELD_NAME) {
+            long aggregate = _currInputProcessed + (_nameStartOffset-1);
+            return new JsonLocation(_getSourceReference(),
+                    -1L, aggregate, _nameStartRow, _nameStartCol);
+        }
+        return new JsonLocation(_getSourceReference(),
+                -1L, _tokenInputTotal-1, _tokenInputRow, _tokenInputCol);
+    }
+
+    @Override
+    public JsonLocation getCurrentLocation() {
+        int columnIndex = _inputPtr - _currInputRowStart + 1; // 1-based
+        return new JsonLocation(_getSourceReference(),
+                -1L, _currInputProcessed + _inputPtr,
+                _currInputRow, columnIndex);
+    }
+
+    // @since 2.7
+    private final void updateLocation()
+    {
+        int pointer = _inputPtr;
+        _tokenInputTotal = _currInputProcessed + pointer;
+        _tokenInputRow = _currInputRow;
+        _tokenInputCol = pointer - _currInputRowStart;
+    }
+
+    // @since 2.7
+    private final void _updateNameStartLocation()
+    {
+        int pointer = _inputPtr;
+        _nameStartOffset = pointer;
+        _nameStartRow = _currInputRow;
+        _nameStartCol = pointer - _currInputRowStart;
+    }
+
+    /*
+    /**********************************************************
+    /* Error reporting
+    /**********************************************************
+     */
+
+    protected void _reportUnexpectedToken(String foundSegment) throws IOException {
+        _reportUnexpectedToken(foundSegment, "'null', 'true', 'false' or NaN");
+    }
+
+    protected void _reportUnexpectedToken(String foundSegment, String message) throws IOException
+    {
+        /* Let's just try to find what appears to be the token, using
+         * regular Java identifier character rules. It's just a heuristic,
+         * nothing fancy here.
+         */
+        StringBuilder messageBuilder = new StringBuilder(foundSegment);
+        while ((_inputPtr < _inputEnd) || _refillBuffer()) {
+            char handler = _inputBuffer[_inputPtr];
+            if (!Character.isJavaIdentifierPart(handler)) {
+                break;
+            }
+            ++_inputPtr;
+            messageBuilder.append(handler);
+            if (messageBuilder.length() >= MAX_ERROR_TOKEN_LENGTH) {
+                messageBuilder.append("...");
+                break;
+            }
+        }
+        _reportError("Unrecognized token '%s': was expecting %s", messageBuilder, message);
+    }
+
+    /*
+    /**********************************************************
+    /* Internal methods, other
+    /**********************************************************
+     */
+
+    private void _endScope(int index) throws JsonParseException {
+        if (index == INT_RBRACKET) {
+            updateLocation();
+            if (!_parsingContext.inArray()) {
+                _reportMismatchedEndMarker(index, '}');
+            }
+            _parsingContext = _parsingContext.clearAndGetParent();
+            _currToken = JsonToken.END_ARRAY;
+        }
+        if (index == INT_RCURLY) {
+            updateLocation();
+            if (!_parsingContext.inObject()) {
+                _reportMismatchedEndMarker(index, ']');
+            }
+            _parsingContext = _parsingContext.clearAndGetParent();
+            _currToken = JsonToken.END_OBJECT;
+        }
+    }
+}
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
diff --git a/src/main/java/com/fasterxml/jackson/core/json/UTF8InputStreamJsonParser.java b/src/main/java/com/fasterxml/jackson/core/json/UTF8InputStreamJsonParser.java
new file mode 100644
index 00000000..360a36b4
--- /dev/null
+++ b/src/main/java/com/fasterxml/jackson/core/json/UTF8InputStreamJsonParser.java
@@ -0,0 +1,2852 @@
+package com.fasterxml.jackson.core.json;
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
+public class UTF8InputStreamJsonParser
+    extends ParserBase
+{
+    final static byte LINE_FEED_VAL = (byte) '\n';
+
+    // This is the main input-code lookup table, fetched eagerly
+    private final static int[] IC_UTF8_TABLE = CharTypes.getInputCodeUtf8();
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
+    private int quadOne;
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
+    public UTF8InputStreamJsonParser(IOContext context, int featureFlags, DataInput dataInput,
+                                     ObjectCodec objectCodec, ByteQuadsCanonicalizer symbolTable,
+                                     int initialByte)
+    {
+        super(context, featureFlags);
+        _objectCodec = objectCodec;
+        _symbols = symbolTable;
+        _inputData = dataInput;
+        _nextByte = initialByte;
+    }
+
+    @Override
+    public ObjectCodec getCodec() {
+        return _objectCodec;
+    }
+
+    @Override
+    public void setCodec(ObjectCodec codecParam) {
+        _objectCodec = codecParam;
+    }
+
+    /*
+    /**********************************************************
+    /* Overrides for life-cycle
+    /**********************************************************
+     */
+
+    @Override
+    public int releaseBuffer(OutputStream outputStream) throws IOException {
+        return 0;
+    }
+
+    @Override
+    public Object getInputSource() {
+        return _inputData;
+    }
+
+    /*
+    /**********************************************************
+    /* Overrides, low-level reading
+    /**********************************************************
+     */
+
+    @Override
+    protected void _closeInput() throws IOException { }
+
+    /**
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
+    }
+
+    /*
+    /**********************************************************
+    /* Public API, data access
+    /**********************************************************
+     */
+
+    @Override
+    public String getText() throws IOException
+    {
+        if (_currToken == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                return _completeAndReturnString(); // only strings can be incomplete
+            }
+            return _textBuffer.contentsAsString();
+        }
+        return _getText(_currToken);
+    }
+
+    @Override
+    public int getText(Writer textWriter) throws IOException
+    {
+        JsonToken token = _currToken;
+        if (token == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                _finishString(); // only strings can be incomplete
+            }
+            return _textBuffer.contentsToWriter(textWriter);
+        }
+        if (token == JsonToken.FIELD_NAME) {
+            String textStr = _parsingContext.getCurrentName();
+            textWriter.write(textStr);
+            return textStr.length();
+        }
+        if (token != null) {
+            if (token.isNumeric()) {
+                return _textBuffer.contentsToWriter(textWriter);
+            }
+            char[] chars = token.asCharArray();
+            textWriter.write(chars);
+            return chars.length;
+        }
+        return 0;
+    }
+
+    // // // Let's override default impls for improved performance
+    @Override
+    public String getValueAsString() throws IOException
+    {
+        if (_currToken == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                return _completeAndReturnString(); // only strings can be incomplete
+            }
+            return _textBuffer.contentsAsString();
+        }
+        if (_currToken == JsonToken.FIELD_NAME) {
+            return getCurrentName();
+        }
+        return super.getValueAsString(null);
+    }
+
+    @Override
+    public String getValueAsString(String defaultValue) throws IOException
+    {
+        if (_currToken == JsonToken.VALUE_STRING) {
+            if (_tokenIncomplete) {
+                _tokenIncomplete = false;
+                return _completeAndReturnString(); // only strings can be incomplete
+            }
+            return _textBuffer.contentsAsString();
+        }
+        if (_currToken == JsonToken.FIELD_NAME) {
+            return getCurrentName();
+        }
+        return super.getValueAsString(defaultValue);
+    }
+
+    @Override
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
+    }
+
+    @Override
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
+    }
+    
+    protected final String _getText(JsonToken token)
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
+    }
+
+    @Override
+    public char[] getTextCharacters() throws IOException
+    {
+        if (_currToken != null) { // null only before/after document
+            switch (_currToken.id()) {
+                
+            case ID_FIELD_NAME:
+                if (!_nameCopied) {
+                    String nameStr = _parsingContext.getCurrentName();
+                    int nameLength = nameStr.length();
+                    if (_nameCopyBuffer == null) {
+                        _nameCopyBuffer = _ioContext.allocNameCopyBuffer(nameLength);
+                    } else if (_nameCopyBuffer.length < nameLength) {
+                        _nameCopyBuffer = new char[nameLength];
+                    }
+                    nameStr.getChars(0, nameLength, _nameCopyBuffer, 0);
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
+    }
+
+    @Override
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
+    }
+
+    @Override
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
+    }
+    
+    @Override
+    public byte[] getBinaryValue(Base64Variant base64Variant) throws IOException
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
+                _binaryValue = _decodeBase64ToBytes(base64Variant);
+            } catch (IllegalArgumentException illegalArgEx) {
+                throw _constructError("Failed to decode VALUE_STRING as base64 ("+ base64Variant +"): "+ illegalArgEx.getMessage());
+            }
+            /* let's clear incomplete only now; allows for accessing other
+             * textual content in error cases
+             */
+            _tokenIncomplete = false;
+        } else { // may actually require conversion...
+            if (_binaryValue == null) {
+                @SuppressWarnings("resource")
+                ByteArrayBuilder byteArrayBuilder = _getByteArrayBuilder();
+                _decodeBase64(getText(), byteArrayBuilder, base64Variant);
+                _binaryValue = byteArrayBuilder.toByteArray();
+            }
+        }
+        return _binaryValue;
+    }
+
+    @Override
+    public int readBinaryValueTo(Base64Variant base64Variant, OutputStream outputStream) throws IOException
+    {
+        // if we have already read the token, just use whatever we may have
+        if (!_tokenIncomplete || _currToken != JsonToken.VALUE_STRING) {
+            byte[] buffer = getBinaryValue(base64Variant);
+            outputStream.write(buffer);
+            return buffer.length;
+        }
+        // otherwise do "real" incremental parsing...
+        byte[] readBuffer = _ioContext.allocBase64Buffer();
+        try {
+            return _readBinaryValue(base64Variant, outputStream, readBuffer);
+        } finally {
+            _ioContext.releaseBase64Buffer(readBuffer);
+        }
+    }
+
+    protected int _readBinaryValue(Base64Variant base64Variant, OutputStream outputStream,
+                                   byte[] inputBuffer) throws IOException
+    {
+        int outputPointer = 0;
+        final int outputLimit = inputBuffer.length - 3;
+        int writtenCount = 0;
+
+        while (true) {
+            // first, we'll skip preceding white space, if any
+            int chars;
+            do {
+                chars = _inputData.readUnsignedByte();
+            } while (chars <= INT_SPACE);
+            int bitCount = base64Variant.decodeBase64Char(chars);
+            if (bitCount < 0) { // reached the end, fair and square?
+                if (chars == INT_QUOTE) {
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
+                writtenCount += outputPointer;
+                outputStream.write(inputBuffer, 0, outputPointer);
+                outputPointer = 0;
+            }
+
+            int decodedValue = bitCount;
+
+            // then second base64 char; can't get padding yet, nor ws
+            chars = _inputData.readUnsignedByte();
+            bitCount = base64Variant.decodeBase64Char(chars);
+            if (bitCount < 0) {
+                bitCount = _decodeBase64Escape(base64Variant, chars, 1);
+            }
+            decodedValue = (decodedValue << 6) | bitCount;
+
+            // third base64 char; can be padding, but not ws
+            chars = _inputData.readUnsignedByte();
+            bitCount = base64Variant.decodeBase64Char(chars);
+
+            // First branch: can get padding (-> 1 byte)
+            if (bitCount < 0) {
+                if (bitCount != Base64Variant.BASE64_VALUE_PADDING) {
+                    // could also just be 'missing'  padding
+                    if (chars == '"' && !base64Variant.usesPadding()) {
+                        decodedValue >>= 4;
+                        inputBuffer[outputPointer++] = (byte) decodedValue;
+                        break;
+                    }
+                    bitCount = _decodeBase64Escape(base64Variant, chars, 2);
+                }
+                if (bitCount == Base64Variant.BASE64_VALUE_PADDING) {
+                    // Ok, must get padding
+                    chars = _inputData.readUnsignedByte();
+                    if (!base64Variant.usesPaddingChar(chars)) {
+                        throw reportInvalidBase64Char(base64Variant, chars, 3, "expected padding character '"+ base64Variant.getPaddingChar()+"'");
+                    }
+                    // Got 12 bits, only need 8, need to shift
+                    decodedValue >>= 4;
+                    inputBuffer[outputPointer++] = (byte) decodedValue;
+                    continue;
+                }
+            }
+            // Nope, 2 or 3 bytes
+            decodedValue = (decodedValue << 6) | bitCount;
+            // fourth and last base64 char; can be padding, but not ws
+            chars = _inputData.readUnsignedByte();
+            bitCount = base64Variant.decodeBase64Char(chars);
+            if (bitCount < 0) {
+                if (bitCount != Base64Variant.BASE64_VALUE_PADDING) {
+                    // could also just be 'missing'  padding
+                    if (chars == '"' && !base64Variant.usesPadding()) {
+                        decodedValue >>= 2;
+                        inputBuffer[outputPointer++] = (byte) (decodedValue >> 8);
+                        inputBuffer[outputPointer++] = (byte) decodedValue;
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
+                    inputBuffer[outputPointer++] = (byte) (decodedValue >> 8);
+                    inputBuffer[outputPointer++] = (byte) decodedValue;
+                    continue;
+                }
+            }
+            // otherwise, our triplet is now complete
+            decodedValue = (decodedValue << 6) | bitCount;
+            inputBuffer[outputPointer++] = (byte) (decodedValue >> 16);
+            inputBuffer[outputPointer++] = (byte) (decodedValue >> 8);
+            inputBuffer[outputPointer++] = (byte) decodedValue;
+        }
+        _tokenIncomplete = false;
+        if (outputPointer > 0) {
+            writtenCount += outputPointer;
+            outputStream.write(inputBuffer, 0, outputPointer);
+        }
+        return writtenCount;
+    }
+
+    /*
+    /**********************************************************
+    /* Public API, traversal, basic
+    /**********************************************************
+     */
+
+    /**
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
+            return _nextTokenAfterName();
+        }
+        // But if we didn't already have a name, and (partially?) decode number,
+        // need to ensure no numeric information is leaked
+        _numTypesValid = NR_UNKNOWN;
+        if (_tokenIncomplete) {
+            _skipJsonString(); // only strings can be partial
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
+            idx = _skipWhitespace();
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
+        String textStr = _parseFieldName(idx);
+        _parsingContext.setCurrentName(textStr);
+        _currToken = JsonToken.FIELD_NAME;
+
+        idx = _skipColonAndReturnNextByte();
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
+            token = handleUnexpectedValue(idx);
+        }
+        _nextToken = token;
+        return _currToken;
+    }
+
+    private final JsonToken _nextTokenOutsideObject(int idx) throws IOException
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
+        return (_currToken = handleUnexpectedValue(idx));
+    }
+    
+    private final JsonToken _nextTokenAfterName()
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
+    }
+
+    @Override
+    public void finishIncompleteToken() throws IOException {
+        if (_tokenIncomplete) {
+            _tokenIncomplete = false;
+            _finishString(); // only strings can be incomplete
+        }
+    }
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
+    @Override
+    public String readNextFieldName() throws IOException
+    {
+        // // // Note: this is almost a verbatim copy of nextToken()
+
+        _numTypesValid = NR_UNKNOWN;
+        if (_currToken == JsonToken.FIELD_NAME) {
+            _nextTokenAfterName();
+            return null;
+        }
+        if (_tokenIncomplete) {
+            _skipJsonString();
+        }
+        int idx = _skipWhitespace();
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
+            idx = _skipWhitespace();
+        }
+        if (!_parsingContext.inObject()) {
+            _nextTokenOutsideObject(idx);
+            return null;
+        }
+
+        final String fieldName = _parseFieldName(idx);
+        _parsingContext.setCurrentName(fieldName);
+        _currToken = JsonToken.FIELD_NAME;
+
+        idx = _skipColonAndReturnNextByte();
+        if (idx == INT_QUOTE) {
+            _tokenIncomplete = true;
+            _nextToken = JsonToken.VALUE_STRING;
+            return fieldName;
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
+            token = handleUnexpectedValue(idx);
+        }
+        _nextToken = token;
+        return fieldName;
+    }
+
+    @Override
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
+                    return _completeAndReturnString();
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
+    }
+
+    @Override
+    public int nextIntValueOrDefault(int fallbackValue) throws IOException
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
+            return fallbackValue;
+        }
+        return (nextJsonToken() == JsonToken.VALUE_NUMBER_INT) ? getIntValue() : fallbackValue;
+    }
+
+    @Override
+    public long nextLong(long fallbackValue) throws IOException
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
+            return fallbackValue;
+        }
+        return (nextJsonToken() == JsonToken.VALUE_NUMBER_INT) ? getLongValue() : fallbackValue;
+    }
+
+    @Override
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
+    }
+
+    /*
+    /**********************************************************
+    /* Internal methods, number parsing
+    /**********************************************************
+     */
+
+    /**
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
+    protected JsonToken _parsePositiveNumber(int codecParam) throws IOException
+    {
+        char[] charBuffer = _textBuffer.emptyAndGetCurrentSegment();
+        int bufferIndex;
+
+        // One special case: if first char is 0, must not be followed by a digit.
+        // Gets bit tricky as we only want to retain 0 if it's the full value
+        if (codecParam == INT_0) {
+            codecParam = _skipLeadingZeros();
+            if (codecParam <= INT_9 && codecParam >= INT_0) { // skip if followed by digit
+                bufferIndex = 0;
+            } else {
+                charBuffer[0] = '0';
+                bufferIndex = 1;
+            }
+        } else {
+            charBuffer[0] = (char) codecParam;
+            codecParam = _inputData.readUnsignedByte();
+            bufferIndex = 1;
+        }
+        int integerLength = bufferIndex;
+
+        // With this, we have a nice and tight loop:
+        while (codecParam <= INT_9 && codecParam >= INT_0) {
+            ++integerLength;
+            charBuffer[bufferIndex++] = (char) codecParam;
+            codecParam = _inputData.readUnsignedByte();
+        }
+        if (codecParam == '.' || codecParam == 'e' || codecParam == 'E') {
+            return _parseFloatLiteral(charBuffer, bufferIndex, codecParam, false, integerLength);
+        }
+        _textBuffer.setCurrentLength(bufferIndex);
+        // As per [core#105], need separating space between root values; check here
+        if (_parsingContext.inRoot()) {
+            _verifyRootWhitespace();
+        } else {
+            _nextByte = codecParam;
+        }
+        // And there we have it!
+        return resetInt(false, integerLength);
+    }
+    
+    protected JsonToken _parseNegativeNumber() throws IOException
+    {
+        char[] charBuffer = _textBuffer.emptyAndGetCurrentSegment();
+        int bufferIndex = 0;
+
+        // Need to prepend sign?
+        charBuffer[bufferIndex++] = '-';
+        int codecParam = _inputData.readUnsignedByte();
+        charBuffer[bufferIndex++] = (char) codecParam;
+        // Note: must be followed by a digit
+        if (codecParam <= INT_0) {
+            // One special case: if first char is 0 need to check no leading zeroes
+            if (codecParam == INT_0) {
+                codecParam = _skipLeadingZeros();
+            } else {
+                return _handleIllegalNumberStart(codecParam, true);
+            }
+        } else {
+            if (codecParam > INT_9) {
+                return _handleIllegalNumberStart(codecParam, true);
+            }
+            codecParam = _inputData.readUnsignedByte();
+        }
+        // Ok: we can first just add digit we saw first:
+        int integerLength = 1;
+
+        // With this, we have a nice and tight loop:
+        while (codecParam <= INT_9 && codecParam >= INT_0) {
+            ++integerLength;
+            charBuffer[bufferIndex++] = (char) codecParam;
+            codecParam = _inputData.readUnsignedByte();
+        }
+        if (codecParam == '.' || codecParam == 'e' || codecParam == 'E') {
+            return _parseFloatLiteral(charBuffer, bufferIndex, codecParam, true, integerLength);
+        }
+        _textBuffer.setCurrentLength(bufferIndex);
+        // As per [core#105], need separating space between root values; check here
+        _nextByte = codecParam;
+        if (_parsingContext.inRoot()) {
+            _verifyRootWhitespace();
+        }
+        // And there we have it!
+        return resetInt(true, integerLength);
+    }
+
+    /**
+     * Method called when we have seen one zero, and want to ensure
+     * it is not followed by another, or, if leading zeroes allowed,
+     * skipped redundant ones.
+     *
+     * @return Character immediately following zeroes
+     */
+    private final int _skipLeadingZeros() throws IOException
+    {
+        int chars = _inputData.readUnsignedByte();
+        // if not followed by a number (probably '.'); return zero as is, to be included
+        if (chars < INT_0 || chars > INT_9) {
+            return chars;
+        }
+        // we may want to allow leading zeroes them, after all...
+        if (!isEnabled(Feature.ALLOW_NUMERIC_LEADING_ZEROS)) {
+            reportInvalidNumber("Leading zeroes not allowed");
+        }
+        // if so, just need to skip either all zeroes (if followed by number); or all but one (if non-number)
+        while (chars == INT_0) {
+            chars = _inputData.readUnsignedByte();
+        }
+        return chars;
+    }
+
+    private final JsonToken _parseFloatLiteral(char[] charBuffer, int bufferIndex, int codecParam,
+                                               boolean isNeg, int integerDigits) throws IOException
+    {
+        int fractionLength = 0;
+
+        // And then see if we get other parts
+        if (codecParam == INT_PERIOD) { // yes, fraction
+            charBuffer[bufferIndex++] = (char) codecParam;
+
+            fract_loop:
+            while (true) {
+                codecParam = _inputData.readUnsignedByte();
+                if (codecParam < INT_0 || codecParam > INT_9) {
+                    break fract_loop;
+                }
+                ++fractionLength;
+                if (bufferIndex >= charBuffer.length) {
+                    charBuffer = _textBuffer.finishCurrentSegment();
+                    bufferIndex = 0;
+                }
+                charBuffer[bufferIndex++] = (char) codecParam;
+            }
+            // must be followed by sequence of ints, one minimum
+            if (fractionLength == 0) {
+                reportUnexpectedNumberChar(codecParam, "Decimal point not followed by a digit");
+            }
+        }
+
+        int exponentLength = 0;
+        if (codecParam == INT_e || codecParam == INT_E) { // exponent?
+            if (bufferIndex >= charBuffer.length) {
+                charBuffer = _textBuffer.finishCurrentSegment();
+                bufferIndex = 0;
+            }
+            charBuffer[bufferIndex++] = (char) codecParam;
+            codecParam = _inputData.readUnsignedByte();
+            // Sign indicator?
+            if (codecParam == '-' || codecParam == '+') {
+                if (bufferIndex >= charBuffer.length) {
+                    charBuffer = _textBuffer.finishCurrentSegment();
+                    bufferIndex = 0;
+                }
+                charBuffer[bufferIndex++] = (char) codecParam;
+                codecParam = _inputData.readUnsignedByte();
+            }
+            while (codecParam <= INT_9 && codecParam >= INT_0) {
+                ++exponentLength;
+                if (bufferIndex >= charBuffer.length) {
+                    charBuffer = _textBuffer.finishCurrentSegment();
+                    bufferIndex = 0;
+                }
+                charBuffer[bufferIndex++] = (char) codecParam;
+                codecParam = _inputData.readUnsignedByte();
+            }
+            // must be followed by sequence of ints, one minimum
+            if (exponentLength == 0) {
+                reportUnexpectedNumberChar(codecParam, "Exponent indicator not followed by a digit");
+            }
+        }
+
+        // Ok; unless we hit end-of-input, need to push last char read back
+        // As per #105, need separating space between root values; check here
+        _nextByte = codecParam;
+        if (_parsingContext.inRoot()) {
+            _verifyRootWhitespace();
+        }
+        _textBuffer.setCurrentLength(bufferIndex);
+
+        // And there we have it!
+        return resetFloat(isNeg, integerDigits, fractionLength, exponentLength);
+    }
+
+    /**
+     * Method called to ensure that a root-value is followed by a space token,
+     * if possible.
+     *<p>
+     * NOTE: with {@link DataInput} source, not really feasible, up-front.
+     * If we did want, we could rearrange things to require space before
+     * next read, but initially let's just do nothing.
+     */
+    private final void _verifyRootWhitespace() throws IOException
+    {
+        int chars = _nextByte;
+        if (chars <= INT_SPACE) {
+            _nextByte = -1;
+            if (chars == INT_CR || chars == INT_LF) {
+                ++_currInputRow;
+            }
+            return;
+        }
+        _reportMissingRootWS(chars);
+    }
+
+    /*
+    /**********************************************************
+    /* Internal methods, secondary parsing
+    /**********************************************************
+     */
+    
+    protected final String _parseFieldName(int idx) throws IOException
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
+        final int[] codeUnits = _icLatin1;
+
+        int quad = _inputData.readUnsignedByte();
+
+        if (codeUnits[quad] == 0) {
+            idx = _inputData.readUnsignedByte();
+            if (codeUnits[idx] == 0) {
+                quad = (quad << 8) | idx;
+                idx = _inputData.readUnsignedByte();
+                if (codeUnits[idx] == 0) {
+                    quad = (quad << 8) | idx;
+                    idx = _inputData.readUnsignedByte();
+                    if (codeUnits[idx] == 0) {
+                        quad = (quad << 8) | idx;
+                        idx = _inputData.readUnsignedByte();
+                        if (codeUnits[idx] == 0) {
+                            quadOne = quad;
+                            return _parseMediumFieldName(idx);
+                        }
+                        if (idx == INT_QUOTE) { // 4 byte/char case or broken
+                            return findFieldName(quad, 4);
+                        }
+                        return parseEscapedName(quad, idx, 4);
+                    }
+                    if (idx == INT_QUOTE) { // 3 byte/char case or broken
+                        return findFieldName(quad, 3);
+                    }
+                    return parseEscapedName(quad, idx, 3);
+                }                
+                if (idx == INT_QUOTE) { // 2 byte/char case or broken
+                    return findFieldName(quad, 2);
+                }
+                return parseEscapedName(quad, idx, 2);
+            }
+            if (idx == INT_QUOTE) { // one byte/char case or broken
+                return findFieldName(quad, 1);
+            }
+            return parseEscapedName(quad, idx, 1);
+        }     
+        if (quad == INT_QUOTE) { // special case, ""
+            return "";
+        }
+        return parseEscapedName(0, quad, 0); // quoting or invalid char
+    }
+
+    private final String _parseMediumFieldName(int secondQuad) throws IOException
+    {
+        final int[] codeUnits = _icLatin1;
+
+        // Ok, got 5 name bytes so far
+        int idx = _inputData.readUnsignedByte();
+        if (codeUnits[idx] != 0) {
+            if (idx == INT_QUOTE) { // 5 bytes
+                return findFieldName(quadOne, secondQuad, 1);
+            }
+            return parseEscapedName(quadOne, secondQuad, idx, 1); // quoting or invalid char
+        }
+        secondQuad = (secondQuad << 8) | idx;
+        idx = _inputData.readUnsignedByte();
+        if (codeUnits[idx] != 0) {
+            if (idx == INT_QUOTE) { // 6 bytes
+                return findFieldName(quadOne, secondQuad, 2);
+            }
+            return parseEscapedName(quadOne, secondQuad, idx, 2);
+        }
+        secondQuad = (secondQuad << 8) | idx;
+        idx = _inputData.readUnsignedByte();
+        if (codeUnits[idx] != 0) {
+            if (idx == INT_QUOTE) { // 7 bytes
+                return findFieldName(quadOne, secondQuad, 3);
+            }
+            return parseEscapedName(quadOne, secondQuad, idx, 3);
+        }
+        secondQuad = (secondQuad << 8) | idx;
+        idx = _inputData.readUnsignedByte();
+        if (codeUnits[idx] != 0) {
+            if (idx == INT_QUOTE) { // 8 bytes
+                return findFieldName(quadOne, secondQuad, 4);
+            }
+            return parseEscapedName(quadOne, secondQuad, idx, 4);
+        }
+        return _parseMediumName(idx, secondQuad);
+    }
+
+    private final String _parseMediumName(int thirdQuad, final int secondQuad) throws IOException
+    {
+        final int[] codeUnits = _icLatin1;
+
+        // Got 9 name bytes so far
+        int idx = _inputData.readUnsignedByte();
+        if (codeUnits[idx] != 0) {
+            if (idx == INT_QUOTE) { // 9 bytes
+                return findFieldName(quadOne, secondQuad, thirdQuad, 1);
+            }
+            return parseEscapedName(quadOne, secondQuad, thirdQuad, idx, 1);
+        }
+        thirdQuad = (thirdQuad << 8) | idx;
+        idx = _inputData.readUnsignedByte();
+        if (codeUnits[idx] != 0) {
+            if (idx == INT_QUOTE) { // 10 bytes
+                return findFieldName(quadOne, secondQuad, thirdQuad, 2);
+            }
+            return parseEscapedName(quadOne, secondQuad, thirdQuad, idx, 2);
+        }
+        thirdQuad = (thirdQuad << 8) | idx;
+        idx = _inputData.readUnsignedByte();
+        if (codeUnits[idx] != 0) {
+            if (idx == INT_QUOTE) { // 11 bytes
+                return findFieldName(quadOne, secondQuad, thirdQuad, 3);
+            }
+            return parseEscapedName(quadOne, secondQuad, thirdQuad, idx, 3);
+        }
+        thirdQuad = (thirdQuad << 8) | idx;
+        idx = _inputData.readUnsignedByte();
+        if (codeUnits[idx] != 0) {
+            if (idx == INT_QUOTE) { // 12 bytes
+                return findFieldName(quadOne, secondQuad, thirdQuad, 4);
+            }
+            return parseEscapedName(quadOne, secondQuad, thirdQuad, idx, 4);
+        }
+        return _parseLongFieldName(idx, secondQuad, thirdQuad);
+    }
+    
+    private final String _parseLongFieldName(int quad, final int secondQuad, int thirdQuad) throws IOException
+    {
+        _quadBuffer[0] = quadOne;
+        _quadBuffer[1] = secondQuad;
+        _quadBuffer[2] = thirdQuad;
+
+        // As explained above, will ignore UTF-8 encoding at this point
+        final int[] codeUnits = _icLatin1;
+        int quadCount = 3;
+
+        while (true) {
+            int idx = _inputData.readUnsignedByte();
+            if (codeUnits[idx] != 0) {
+                if (idx == INT_QUOTE) {
+                    return findFieldName(_quadBuffer, quadCount, quad, 1);
+                }
+                return parseQuotedName(_quadBuffer, quadCount, quad, idx, 1);
+            }
+
+            quad = (quad << 8) | idx;
+            idx = _inputData.readUnsignedByte();
+            if (codeUnits[idx] != 0) {
+                if (idx == INT_QUOTE) {
+                    return findFieldName(_quadBuffer, quadCount, quad, 2);
+                }
+                return parseQuotedName(_quadBuffer, quadCount, quad, idx, 2);
+            }
+
+            quad = (quad << 8) | idx;
+            idx = _inputData.readUnsignedByte();
+            if (codeUnits[idx] != 0) {
+                if (idx == INT_QUOTE) {
+                    return findFieldName(_quadBuffer, quadCount, quad, 3);
+                }
+                return parseQuotedName(_quadBuffer, quadCount, quad, idx, 3);
+            }
+
+            quad = (quad << 8) | idx;
+            idx = _inputData.readUnsignedByte();
+            if (codeUnits[idx] != 0) {
+                if (idx == INT_QUOTE) {
+                    return findFieldName(_quadBuffer, quadCount, quad, 4);
+                }
+                return parseQuotedName(_quadBuffer, quadCount, quad, idx, 4);
+            }
+
+            // Nope, no end in sight. Need to grow quad array etc
+            if (quadCount >= _quadBuffer.length) {
+                _quadBuffer = growArrayBy(_quadBuffer, quadCount);
+            }
+            _quadBuffer[quadCount++] = quad;
+            quad = idx;
+        }
+    }
+
+    private final String parseEscapedName(int firstQuad, int chars, int trailingQuadBytes) throws IOException {
+        return parseQuotedName(_quadBuffer, 0, firstQuad, chars, trailingQuadBytes);
+    }
+
+    private final String parseEscapedName(int firstQuad, int secondQuad, int chars, int trailingQuadBytes) throws IOException {
+        _quadBuffer[0] = firstQuad;
+        return parseQuotedName(_quadBuffer, 1, secondQuad, chars, trailingQuadBytes);
+    }
+
+    private final String parseEscapedName(int firstQuad, int secondQuad, int thirdQuad, int chars, int trailingQuadBytes) throws IOException {
+        _quadBuffer[0] = firstQuad;
+        _quadBuffer[1] = secondQuad;
+        return parseQuotedName(_quadBuffer, 2, thirdQuad, chars, trailingQuadBytes);
+    }
+    
+    /**
+     * Slower parsing method which is generally branched to when
+     * an escape sequence is detected (or alternatively for long
+     * names, one crossing input buffer boundary).
+     * Needs to be able to handle more exceptional cases, gets slower,
+     * and hance is offlined to a separate method.
+     */
+    protected final String parseQuotedName(int[] quadUnits, int quadCount, int currentQuadValue, int chars,
+                                           int currentQuadBytesCount) throws IOException
+    {
+        /* 25-Nov-2008, tatu: This may seem weird, but here we do not want to worry about
+         *   UTF-8 decoding yet. Rather, we'll assume that part is ok (if not it will get
+         *   caught later on), and just handle quotes and backslashes here.
+         */
+        final int[] codeUnits = _icLatin1;
+
+        while (true) {
+            if (codeUnits[chars] != 0) {
+                if (chars == INT_QUOTE) { // we are done
+                    break;
+                }
+                // Unquoted white space?
+                if (chars != INT_BACKSLASH) {
+                    // As per [JACKSON-208], call can now return:
+                    _throwUnquotedSpace(chars, "name");
+                } else {
+                    // Nope, escape sequence
+                    chars = _decodeEscaped();
+                }
+                /* Oh crap. May need to UTF-8 (re-)encode it, if it's
+                 * beyond 7-bit ascii. Gets pretty messy.
+                 * If this happens often, may want to use different name
+                 * canonicalization to avoid these hits.
+                 */
+                if (chars > 127) {
+                    // Ok, we'll need room for first byte right away
+                    if (currentQuadBytesCount >= 4) {
+                        if (quadCount >= quadUnits.length) {
+                            _quadBuffer = quadUnits = growArrayBy(quadUnits, quadUnits.length);
+                        }
+                        quadUnits[quadCount++] = currentQuadValue;
+                        currentQuadValue = 0;
+                        currentQuadBytesCount = 0;
+                    }
+                    if (chars < 0x800) { // 2-byte
+                        currentQuadValue = (currentQuadValue << 8) | (0xc0 | (chars >> 6));
+                        ++currentQuadBytesCount;
+                        // Second byte gets output below:
+                    } else { // 3 bytes; no need to worry about surrogates here
+                        currentQuadValue = (currentQuadValue << 8) | (0xe0 | (chars >> 12));
+                        ++currentQuadBytesCount;
+                        // need room for middle byte?
+                        if (currentQuadBytesCount >= 4) {
+                            if (quadCount >= quadUnits.length) {
+                                _quadBuffer = quadUnits = growArrayBy(quadUnits, quadUnits.length);
+                            }
+                            quadUnits[quadCount++] = currentQuadValue;
+                            currentQuadValue = 0;
+                            currentQuadBytesCount = 0;
+                        }
+                        currentQuadValue = (currentQuadValue << 8) | (0x80 | ((chars >> 6) & 0x3f));
+                        ++currentQuadBytesCount;
+                    }
+                    // And same last byte in both cases, gets output below:
+                    chars = 0x80 | (chars & 0x3f);
+                }
+            }
+            // Ok, we have one more byte to add at any rate:
+            if (currentQuadBytesCount < 4) {
+                ++currentQuadBytesCount;
+                currentQuadValue = (currentQuadValue << 8) | chars;
+            } else {
+                if (quadCount >= quadUnits.length) {
+                    _quadBuffer = quadUnits = growArrayBy(quadUnits, quadUnits.length);
+                }
+                quadUnits[quadCount++] = currentQuadValue;
+                currentQuadValue = chars;
+                currentQuadBytesCount = 1;
+            }
+            chars = _inputData.readUnsignedByte();
+        }
+
+        if (currentQuadBytesCount > 0) {
+            if (quadCount >= quadUnits.length) {
+                _quadBuffer = quadUnits = growArrayBy(quadUnits, quadUnits.length);
+            }
+            quadUnits[quadCount++] = signExtend(currentQuadValue, currentQuadBytesCount);
+        }
+        String nameStr = _symbols.findName(quadUnits, quadCount);
+        if (nameStr == null) {
+            nameStr = addNameFromQuads(quadUnits, quadCount, currentQuadBytesCount);
+        }
+        return nameStr;
+    }
+
+    /**
+     * Method called when we see non-white space character other
+     * than double quote, when expecting a field name.
+     * In standard mode will just throw an exception; but
+     * in non-standard modes may be able to parse name.
+     */
+    protected String _handleUnquotedName(int chars) throws IOException
+    {
+        if (chars == '\'' && isEnabled(Feature.ALLOW_SINGLE_QUOTES)) {
+            return _parseAposFieldName();
+        }
+        if (!isEnabled(Feature.ALLOW_UNQUOTED_FIELD_NAMES)) {
+            char codecParam = (char) _decodeUtf8CharForError(chars);
+            _reportUnexpectedChar(codecParam, "was expecting double-quote to start field name");
+        }
+        /* Also: note that although we use a different table here,
+         * it does NOT handle UTF-8 decoding. It'll just pass those
+         * high-bit codes as acceptable for later decoding.
+         */
+        final int[] codeUnits = CharTypes.getInputCodeUtf8JsNames();
+        // Also: must start with a valid character...
+        if (codeUnits[chars] != 0) {
+            _reportUnexpectedChar(chars, "was expecting either valid name character (for unquoted name) or double-quote (for quoted) to start field name");
+        }
+
+        /* Ok, now; instead of ultra-optimizing parsing here (as with
+         * regular JSON names), let's just use the generic "slow"
+         * variant. Can measure its impact later on if need be
+         */
+        int[] quadUnits = _quadBuffer;
+        int quadCount = 0;
+        int currentQuadValue = 0;
+        int currentQuadBytesCount = 0;
+
+        while (true) {
+            // Ok, we have one more byte to add at any rate:
+            if (currentQuadBytesCount < 4) {
+                ++currentQuadBytesCount;
+                currentQuadValue = (currentQuadValue << 8) | chars;
+            } else {
+                if (quadCount >= quadUnits.length) {
+                    _quadBuffer = quadUnits = growArrayBy(quadUnits, quadUnits.length);
+                }
+                quadUnits[quadCount++] = currentQuadValue;
+                currentQuadValue = chars;
+                currentQuadBytesCount = 1;
+            }
+            chars = _inputData.readUnsignedByte();
+            if (codeUnits[chars] != 0) {
+                break;
+            }
+        }
+        // Note: we must "push back" character read here for future consumption
+        _nextByte = chars;
+        if (currentQuadBytesCount > 0) {
+            if (quadCount >= quadUnits.length) {
+                _quadBuffer = quadUnits = growArrayBy(quadUnits, quadUnits.length);
+            }
+            quadUnits[quadCount++] = currentQuadValue;
+        }
+        String nameStr = _symbols.findName(quadUnits, quadCount);
+        if (nameStr == null) {
+            nameStr = addNameFromQuads(quadUnits, quadCount, currentQuadBytesCount);
+        }
+        return nameStr;
+    }
+
+    /* Parsing to allow optional use of non-standard single quotes.
+     * Plenty of duplicated code;
+     * main reason being to try to avoid slowing down fast path
+     * for valid JSON -- more alternatives, more code, generally
+     * bit slower execution.
+     */
+    protected String _parseAposFieldName() throws IOException
+    {
+        int chars = _inputData.readUnsignedByte();
+        if (chars == '\'') { // special case, ''
+            return "";
+        }
+        int[] quadUnits = _quadBuffer;
+        int quadCount = 0;
+        int currentQuadValue = 0;
+        int currentQuadBytesCount = 0;
+
+        // Copied from parseEscapedFieldName, with minor mods:
+
+        final int[] codeUnits = _icLatin1;
+
+        while (true) {
+            if (chars == '\'') {
+                break;
+            }
+            // additional check to skip handling of double-quotes
+            if (chars != '"' && codeUnits[chars] != 0) {
+                if (chars != '\\') {
+                    // Unquoted white space?
+                    // As per [JACKSON-208], call can now return:
+                    _throwUnquotedSpace(chars, "name");
+                } else {
+                    // Nope, escape sequence
+                    chars = _decodeEscaped();
+                }
+                /* Oh crap. May need to UTF-8 (re-)encode it, if it's  beyond
+                 * 7-bit ASCII. Gets pretty messy. If this happens often, may want
+                 * to use different name canonicalization to avoid these hits.
+                 */
+                if (chars > 127) {
+                    // Ok, we'll need room for first byte right away
+                    if (currentQuadBytesCount >= 4) {
+                        if (quadCount >= quadUnits.length) {
+                            _quadBuffer = quadUnits = growArrayBy(quadUnits, quadUnits.length);
+                        }
+                        quadUnits[quadCount++] = currentQuadValue;
+                        currentQuadValue = 0;
+                        currentQuadBytesCount = 0;
+                    }
+                    if (chars < 0x800) { // 2-byte
+                        currentQuadValue = (currentQuadValue << 8) | (0xc0 | (chars >> 6));
+                        ++currentQuadBytesCount;
+                        // Second byte gets output below:
+                    } else { // 3 bytes; no need to worry about surrogates here
+                        currentQuadValue = (currentQuadValue << 8) | (0xe0 | (chars >> 12));
+                        ++currentQuadBytesCount;
+                        // need room for middle byte?
+                        if (currentQuadBytesCount >= 4) {
+                            if (quadCount >= quadUnits.length) {
+                                _quadBuffer = quadUnits = growArrayBy(quadUnits, quadUnits.length);
+                            }
+                            quadUnits[quadCount++] = currentQuadValue;
+                            currentQuadValue = 0;
+                            currentQuadBytesCount = 0;
+                        }
+                        currentQuadValue = (currentQuadValue << 8) | (0x80 | ((chars >> 6) & 0x3f));
+                        ++currentQuadBytesCount;
+                    }
+                    // And same last byte in both cases, gets output below:
+                    chars = 0x80 | (chars & 0x3f);
+                }
+            }
+            // Ok, we have one more byte to add at any rate:
+            if (currentQuadBytesCount < 4) {
+                ++currentQuadBytesCount;
+                currentQuadValue = (currentQuadValue << 8) | chars;
+            } else {
+                if (quadCount >= quadUnits.length) {
+                    _quadBuffer = quadUnits = growArrayBy(quadUnits, quadUnits.length);
+                }
+                quadUnits[quadCount++] = currentQuadValue;
+                currentQuadValue = chars;
+                currentQuadBytesCount = 1;
+            }
+            chars = _inputData.readUnsignedByte();
+        }
+
+        if (currentQuadBytesCount > 0) {
+            if (quadCount >= quadUnits.length) {
+                _quadBuffer = quadUnits = growArrayBy(quadUnits, quadUnits.length);
+            }
+            quadUnits[quadCount++] = signExtend(currentQuadValue, currentQuadBytesCount);
+        }
+        String nameStr = _symbols.findName(quadUnits, quadCount);
+        if (nameStr == null) {
+            nameStr = addNameFromQuads(quadUnits, quadCount, currentQuadBytesCount);
+        }
+        return nameStr;
+    }
+
+    /*
+    /**********************************************************
+    /* Internal methods, symbol (name) handling
+    /**********************************************************
+     */
+
+    private final String findFieldName(int firstQuad, int trailingQuadBytes) throws JsonParseException
+    {
+        firstQuad = signExtend(firstQuad, trailingQuadBytes);
+        // Usually we'll find it from the canonical symbol table already
+        String nameStr = _symbols.findName(firstQuad);
+        if (nameStr != null) {
+            return nameStr;
+        }
+        // If not, more work. We'll need add stuff to buffer
+        _quadBuffer[0] = firstQuad;
+        return addNameFromQuads(_quadBuffer, 1, trailingQuadBytes);
+    }
+
+    private final String findFieldName(int firstQuad, int secondQuad, int trailingQuadBytes) throws JsonParseException
+    {
+        secondQuad = signExtend(secondQuad, trailingQuadBytes);
+        // Usually we'll find it from the canonical symbol table already
+        String nameStr = _symbols.findName(firstQuad, secondQuad);
+        if (nameStr != null) {
+            return nameStr;
+        }
+        // If not, more work. We'll need add stuff to buffer
+        _quadBuffer[0] = firstQuad;
+        _quadBuffer[1] = secondQuad;
+        return addNameFromQuads(_quadBuffer, 2, trailingQuadBytes);
+    }
+
+    private final String findFieldName(int firstQuad, int secondQuad, int thirdQuad, int trailingQuadBytes) throws JsonParseException
+    {
+        thirdQuad = signExtend(thirdQuad, trailingQuadBytes);
+        String nameStr = _symbols.findName(firstQuad, secondQuad, thirdQuad);
+        if (nameStr != null) {
+            return nameStr;
+        }
+        int[] quadUnits = _quadBuffer;
+        quadUnits[0] = firstQuad;
+        quadUnits[1] = secondQuad;
+        quadUnits[2] = signExtend(thirdQuad, trailingQuadBytes);
+        return addNameFromQuads(quadUnits, 3, trailingQuadBytes);
+    }
+    
+    private final String findFieldName(int[] quadUnits, int quadCount, int finalQuadVal, int trailingQuadBytes) throws JsonParseException
+    {
+        if (quadCount >= quadUnits.length) {
+            _quadBuffer = quadUnits = growArrayBy(quadUnits, quadUnits.length);
+        }
+        quadUnits[quadCount++] = signExtend(finalQuadVal, trailingQuadBytes);
+        String nameStr = _symbols.findName(quadUnits, quadCount);
+        if (nameStr == null) {
+            return addNameFromQuads(quadUnits, quadCount, trailingQuadBytes);
+        }
+        return nameStr;
+    }
+
+    /**
+     * This is the main workhorse method used when we take a symbol
+     * table miss. It needs to demultiplex individual bytes, decode
+     * multi-byte chars (if any), and then construct Name instance
+     * and add it to the symbol table.
+     */
+    private final String addNameFromQuads(int[] quadUnits, int quadCount, int trailingQuadBytes) throws JsonParseException
+    {
+        /* Ok: must decode UTF-8 chars. No other validation is
+         * needed, since unescaping has been done earlier as necessary
+         * (as well as error reporting for unescaped control chars)
+         */
+        // 4 bytes per quad, except last one maybe less
+        int byteLength = (quadCount << 2) - 4 + trailingQuadBytes;
+
+        /* And last one is not correctly aligned (leading zero bytes instead
+         * need to shift a bit, instead of trailing). Only need to shift it
+         * for UTF-8 decoding; need revert for storage (since key will not
+         * be aligned, to optimize lookup speed)
+         */
+        int finalQuadVal;
+
+        if (trailingQuadBytes < 4) {
+            finalQuadVal = quadUnits[quadCount -1];
+            // 8/16/24 bit left shift
+            quadUnits[quadCount -1] = (finalQuadVal << ((4 - trailingQuadBytes) << 3));
+        } else {
+            finalQuadVal = 0;
+        }
+
+        // Need some working space, TextBuffer works well:
+        char[] charBuffer = _textBuffer.emptyAndGetCurrentSegment();
+        int charIndex = 0;
+
+        for (int index = 0; index < byteLength; ) {
+            int chars = quadUnits[index >> 2]; // current quad, need to shift+mask
+            int byteIndex = (index & 3);
+            chars = (chars >> ((3 - byteIndex) << 3)) & 0xFF;
+            ++index;
+
+            if (chars > 127) { // multi-byte
+                int requiredBytes;
+                if ((chars & 0xE0) == 0xC0) { // 2 bytes (0x0080 - 0x07FF)
+                    chars &= 0x1F;
+                    requiredBytes = 1;
+                } else if ((chars & 0xF0) == 0xE0) { // 3 bytes (0x0800 - 0xFFFF)
+                    chars &= 0x0F;
+                    requiredBytes = 2;
+                } else if ((chars & 0xF8) == 0xF0) { // 4 bytes; double-char with surrogates and all...
+                    chars &= 0x07;
+                    requiredBytes = 3;
+                } else { // 5- and 6-byte chars not valid xml chars
+                    _reportInvalidStartByte(chars);
+                    requiredBytes = chars = 1; // never really gets this far
+                }
+                if ((index + requiredBytes) > byteLength) {
+                    _reportInvalidEOF(" in field name", JsonToken.FIELD_NAME);
+                }
+                
+                // Ok, always need at least one more:
+                int secondCharCode = quadUnits[index >> 2]; // current quad, need to shift+mask
+                byteIndex = (index & 3);
+                secondCharCode = (secondCharCode >> ((3 - byteIndex) << 3));
+                ++index;
+                
+                if ((secondCharCode & 0xC0) != 0x080) {
+                    _reportInvalidMiddleByte(secondCharCode);
+                }
+                chars = (chars << 6) | (secondCharCode & 0x3F);
+                if (requiredBytes > 1) {
+                    secondCharCode = quadUnits[index >> 2];
+                    byteIndex = (index & 3);
+                    secondCharCode = (secondCharCode >> ((3 - byteIndex) << 3));
+                    ++index;
+                    
+                    if ((secondCharCode & 0xC0) != 0x080) {
+                        _reportInvalidMiddleByte(secondCharCode);
+                    }
+                    chars = (chars << 6) | (secondCharCode & 0x3F);
+                    if (requiredBytes > 2) { // 4 bytes? (need surrogates on output)
+                        secondCharCode = quadUnits[index >> 2];
+                        byteIndex = (index & 3);
+                        secondCharCode = (secondCharCode >> ((3 - byteIndex) << 3));
+                        ++index;
+                        if ((secondCharCode & 0xC0) != 0x080) {
+                            _reportInvalidMiddleByte(secondCharCode & 0xFF);
+                        }
+                        chars = (chars << 6) | (secondCharCode & 0x3F);
+                    }
+                }
+                if (requiredBytes > 2) { // surrogate pair? once again, let's output one here, one later on
+                    chars -= 0x10000; // to normalize it starting with 0x0
+                    if (charIndex >= charBuffer.length) {
+                        charBuffer = _textBuffer.expandCurrentSegment();
+                    }
+                    charBuffer[charIndex++] = (char) (0xD800 + (chars >> 10));
+                    chars = 0xDC00 | (chars & 0x03FF);
+                }
+            }
+            if (charIndex >= charBuffer.length) {
+                charBuffer = _textBuffer.expandCurrentSegment();
+            }
+            charBuffer[charIndex++] = (char) chars;
+        }
+
+        // Ok. Now we have the character array, and can construct the String
+        String rootLabel = new String(charBuffer, 0, charIndex);
+        // And finally, un-align if necessary
+        if (trailingQuadBytes < 4) {
+            quadUnits[quadCount -1] = finalQuadVal;
+        }
+        return _symbols.addName(rootLabel, quadUnits, quadCount);
+    }
+
+    /*
+    /**********************************************************
+    /* Internal methods, String value parsing
+    /**********************************************************
+     */
+
+    @Override
+    protected void _finishString() throws IOException
+    {
+        int bufferIndex = 0;
+        char[] charBuffer = _textBuffer.emptyAndGetCurrentSegment();
+        final int[] codeUnits = IC_UTF8_TABLE;
+        final int endPos = charBuffer.length;
+
+        do {
+            int codecParam = _inputData.readUnsignedByte();
+            if (codeUnits[codecParam] != 0) {
+                if (codecParam == INT_QUOTE) {
+                    _textBuffer.setCurrentLength(bufferIndex);
+                    return;
+                }
+                _finishStringFull(charBuffer, bufferIndex, codecParam);
+                return;
+            }
+            charBuffer[bufferIndex++] = (char) codecParam;
+        } while (bufferIndex < endPos);
+        _finishStringFull(charBuffer, bufferIndex, _inputData.readUnsignedByte());
+    }
+
+    private String _completeAndReturnString() throws IOException
+    {
+        int bufferIndex = 0;
+        char[] charBuffer = _textBuffer.emptyAndGetCurrentSegment();
+        final int[] codeUnits = IC_UTF8_TABLE;
+        final int endPos = charBuffer.length;
+
+        do {
+            int codecParam = _inputData.readUnsignedByte();
+            if (codeUnits[codecParam] != 0) {
+                if (codecParam == INT_QUOTE) {
+                    return _textBuffer.setCurrentAndReturn(bufferIndex);
+                }
+                _finishStringFull(charBuffer, bufferIndex, codecParam);
+                return _textBuffer.contentsAsString();
+            }
+            charBuffer[bufferIndex++] = (char) codecParam;
+        } while (bufferIndex < endPos);
+        _finishStringFull(charBuffer, bufferIndex, _inputData.readUnsignedByte());
+        return _textBuffer.contentsAsString();
+    }
+    
+    private final void _finishStringFull(char[] charBuffer, int bufferIndex, int codecParam)
+        throws IOException
+    {
+        // Here we do want to do full decoding, hence:
+        final int[] codeUnits = IC_UTF8_TABLE;
+        int endPos = charBuffer.length;
+
+        main_loop:
+        for (;; codecParam = _inputData.readUnsignedByte()) {
+            // Then the tight ASCII non-funny-char loop:
+            while (codeUnits[codecParam] == 0) {
+                if (bufferIndex >= endPos) {
+                    charBuffer = _textBuffer.finishCurrentSegment();
+                    bufferIndex = 0;
+                    endPos = charBuffer.length;
+                }
+                charBuffer[bufferIndex++] = (char) codecParam;
+                codecParam = _inputData.readUnsignedByte();
+            }
+            // Ok: end marker, escape or multi-byte?
+            if (codecParam == INT_QUOTE) {
+                break main_loop;
+            }
+            switch (codeUnits[codecParam]) {
+            case 1: // backslash
+                codecParam = _decodeEscaped();
+                break;
+            case 2: // 2-byte UTF
+                codecParam = decodeUtf8_2(codecParam);
+                break;
+            case 3: // 3-byte UTF
+                codecParam = decodeUtf8ThreeBytes(codecParam);
+                break;
+            case 4: // 4-byte UTF
+                codecParam = _decodeUtf8_4Bytes(codecParam);
+                // Let's add first part right away:
+                charBuffer[bufferIndex++] = (char) (0xD800 | (codecParam >> 10));
+                if (bufferIndex >= charBuffer.length) {
+                    charBuffer = _textBuffer.finishCurrentSegment();
+                    bufferIndex = 0;
+                    endPos = charBuffer.length;
+                }
+                codecParam = 0xDC00 | (codecParam & 0x3FF);
+                // And let the other char output down below
+                break;
+            default:
+                if (codecParam < INT_SPACE) {
+                    _throwUnquotedSpace(codecParam, "string value");
+                } else {
+                    // Is this good enough error message?
+                    _reportInvalidCharacter(codecParam);
+                }
+            }
+            // Need more room?
+            if (bufferIndex >= charBuffer.length) {
+                charBuffer = _textBuffer.finishCurrentSegment();
+                bufferIndex = 0;
+                endPos = charBuffer.length;
+            }
+            // Ok, let's add char to output:
+            charBuffer[bufferIndex++] = (char) codecParam;
+        }
+        _textBuffer.setCurrentLength(bufferIndex);
+    }
+
+    /**
+     * Method called to skim through rest of unparsed String value,
+     * if it is not needed. This can be done bit faster if contents
+     * need not be stored for future access.
+     */
+    protected void _skipJsonString() throws IOException
+    {
+        _tokenIncomplete = false;
+
+        // Need to be fully UTF-8 aware here:
+        final int[] codeUnits = IC_UTF8_TABLE;
+
+        main_loop:
+        while (true) {
+            int codecParam;
+
+            ascii_loop:
+            while (true) {
+                codecParam = _inputData.readUnsignedByte();
+                if (codeUnits[codecParam] != 0) {
+                    break ascii_loop;
+                }
+            }
+            // Ok: end marker, escape or multi-byte?
+            if (codecParam == INT_QUOTE) {
+                break main_loop;
+            }
+            
+            switch (codeUnits[codecParam]) {
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
+                if (codecParam < INT_SPACE) {
+                    _throwUnquotedSpace(codecParam, "string value");
+                } else {
+                    // Is this good enough error message?
+                    _reportInvalidCharacter(codecParam);
+                }
+            }
+        }
+    }
+
+    /**
+     * Method for handling cases where first non-space character
+     * of an expected value token is not legal for standard JSON content.
+     */
+    protected JsonToken handleUnexpectedValue(int codecParam)
+        throws IOException
+    {
+        // Most likely an error, unless we are to allow single-quote-strings
+        switch (codecParam) {
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
+                _nextByte = codecParam;
+               return JsonToken.VALUE_NULL;
+            }
+            // fall through
+        case '}':
+            // Error: neither is valid at this point; valid closers have
+            // been handled earlier
+            _reportUnexpectedChar(codecParam, "expected a value");
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
+            return _handleIllegalNumberStart(_inputData.readUnsignedByte(), false);
+        }
+        // [core#77] Try to decode most likely token
+        if (Character.isJavaIdentifierStart(codecParam)) {
+            _reportUnexpectedToken(codecParam, ""+((char) codecParam), "('true', 'false' or 'null')");
+        }
+        // but if it doesn't look like a token:
+        _reportUnexpectedChar(codecParam, "expected a valid value (number, String, array, object, 'true', 'false' or 'null')");
+        return null;
+    }
+
+    protected JsonToken _finishAposString() throws IOException
+    {
+        int codecParam = 0;
+        // Otherwise almost verbatim copy of _finishString()
+        int bufferIndex = 0;
+        char[] charBuffer = _textBuffer.emptyAndGetCurrentSegment();
+
+        // Here we do want to do full decoding, hence:
+        final int[] codeUnits = IC_UTF8_TABLE;
+
+        main_loop:
+        while (true) {
+            // Then the tight ascii non-funny-char loop:
+            ascii_loop:
+            while (true) {
+                int endPos = charBuffer.length;
+                if (bufferIndex >= charBuffer.length) {
+                    charBuffer = _textBuffer.finishCurrentSegment();
+                    bufferIndex = 0;
+                    endPos = charBuffer.length;
+                }
+                do {
+                    codecParam = _inputData.readUnsignedByte();
+                    if (codecParam == '\'') {
+                        break main_loop;
+                    }
+                    if (codeUnits[codecParam] != 0) {
+                        break ascii_loop;
+                    }
+                    charBuffer[bufferIndex++] = (char) codecParam;
+                } while (bufferIndex < endPos);
+            }
+            switch (codeUnits[codecParam]) {
+            case 1: // backslash
+                codecParam = _decodeEscaped();
+                break;
+            case 2: // 2-byte UTF
+                codecParam = decodeUtf8_2(codecParam);
+                break;
+            case 3: // 3-byte UTF
+                codecParam = decodeUtf8ThreeBytes(codecParam);
+                break;
+            case 4: // 4-byte UTF
+                codecParam = _decodeUtf8_4Bytes(codecParam);
+                // Let's add first part right away:
+                charBuffer[bufferIndex++] = (char) (0xD800 | (codecParam >> 10));
+                if (bufferIndex >= charBuffer.length) {
+                    charBuffer = _textBuffer.finishCurrentSegment();
+                    bufferIndex = 0;
+                }
+                codecParam = 0xDC00 | (codecParam & 0x3FF);
+                // And let the other char output down below
+                break;
+            default:
+                if (codecParam < INT_SPACE) {
+                    _throwUnquotedSpace(codecParam, "string value");
+                }
+                // Is this good enough error message?
+                _reportInvalidCharacter(codecParam);
+            }
+            // Need more room?
+            if (bufferIndex >= charBuffer.length) {
+                charBuffer = _textBuffer.finishCurrentSegment();
+                bufferIndex = 0;
+            }
+            // Ok, let's add char to output:
+            charBuffer[bufferIndex++] = (char) codecParam;
+        }
+        _textBuffer.setCurrentLength(bufferIndex);
+
+        return JsonToken.VALUE_STRING;
+    }
+    
+    /**
+     * Method called if expected numeric value (due to leading sign) does not
+     * look like a number
+     */
+    protected JsonToken _handleIllegalNumberStart(int chars, boolean isNegative)
+        throws IOException
+    {
+        while (chars == 'I') {
+            chars = _inputData.readUnsignedByte();
+            String matchText;
+            if (chars == 'N') {
+                matchText = isNegative ? "-INF" :"+INF";
+            } else if (chars == 'n') {
+                matchText = isNegative ? "-Infinity" :"+Infinity";
+            } else {
+                break;
+            }
+            _matchJsonToken(matchText, 3);
+            if (isEnabled(Feature.ALLOW_NON_NUMERIC_NUMBERS)) {
+                return resetAsNaN(matchText, isNegative ? Double.NEGATIVE_INFINITY : Double.POSITIVE_INFINITY);
+            }
+            _reportError("Non-standard token '"+ matchText +"': enable JsonParser.Feature.ALLOW_NON_NUMERIC_NUMBERS to allow");
+        }
+        reportUnexpectedNumberChar(chars, "expected digit (0-9) to follow minus sign, for valid numeric value");
+        return null;
+    }
+
+    protected final void _matchJsonToken(String tokenLiteral, int idx) throws IOException
+    {
+        final int length = tokenLiteral.length();
+        do {
+            int chars = _inputData.readUnsignedByte();
+            if (chars != tokenLiteral.charAt(idx)) {
+                _reportUnexpectedToken(chars, tokenLiteral.substring(0, idx));
+            }
+        } while (++idx < length);
+
+        int chars = _inputData.readUnsignedByte();
+        if (chars >= '0' && chars != ']' && chars != '}') { // expected/allowed chars
+            _verifyMatchEnd(tokenLiteral, idx, chars);
+        }
+        _nextByte = chars;
+    }
+
+    private final void _verifyMatchEnd(String tokenLiteral, int idx, int chars) throws IOException {
+        // but actually only alphanums are problematic
+        char codecParam = (char) _decodeUtf8CharForError(chars);
+        if (Character.isJavaIdentifierPart(codecParam)) {
+            _reportUnexpectedToken(codecParam, tokenLiteral.substring(0, idx));
+        }
+    }
+
+    /*
+    /**********************************************************
+    /* Internal methods, ws skipping, escape/unescape
+    /**********************************************************
+     */
+
+    private final int _skipWhitespace() throws IOException
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
+    }
+
+    /**
+     * Alternative to {@link #_skipWhitespace} that handles possible {@link EOFException}
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
+            } catch (EOFException eofEx) {
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
+            } catch (EOFException eofEx) {
+                return _eofAsNextChar();
+            }
+        }
+    }
+    
+    private final int _skipWhitespaceAndComments(int idx) throws IOException
+    {
+        while (true) {
+            if (idx > INT_SPACE) {
+                if (idx == INT_SLASH) {
+                    _consumeComment();
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
+    }
+
+    private final int _skipColonAndReturnNextByte() throws IOException
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
+    }
+
+    private final int _skipColon(int idx, boolean hasColon) throws IOException
+    {
+        for (;; idx = _inputData.readUnsignedByte()) {
+            if (idx > INT_SPACE) {
+                if (idx == INT_SLASH) {
+                    _consumeComment();
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
+    }
+
+    private final void _consumeComment() throws IOException
+    {
+        if (!isEnabled(Feature.ALLOW_COMMENTS)) {
+            _reportUnexpectedChar('/', "maybe a (non-standard) comment? (not recognized as one since Feature 'ALLOW_COMMENTS' not enabled for parser)");
+        }
+        int codecParam = _inputData.readUnsignedByte();
+        if (codecParam == '/') {
+            _skipToLineEnd();
+        } else if (codecParam == '*') {
+            _skipCStyleComment();
+        } else {
+            _reportUnexpectedChar(codecParam, "was expecting either '*' or '/' for a comment");
+        }
+    }
+
+    private final void _skipCStyleComment() throws IOException
+    {
+        // Need to be UTF-8 aware here to decode content (for skipping)
+        final int[] codeUnits = CharTypes.getInputCodeComment();
+        int idx = _inputData.readUnsignedByte();
+
+        // Ok: need the matching '*/'
+        main_loop:
+        while (true) {
+            int currCode = codeUnits[idx];
+            if (currCode != 0) {
+                switch (currCode) {
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
+    }
+
+    private final boolean _skipYamlComment() throws IOException
+    {
+        if (!isEnabled(Feature.ALLOW_YAML_COMMENTS)) {
+            return false;
+        }
+        _skipToLineEnd();
+        return true;
+    }
+
+    /**
+     * Method for skipping contents of an input line; usually for CPP
+     * and YAML style comments.
+     */
+    private final void _skipToLineEnd() throws IOException
+    {
+        // Ok: need to find EOF or linefeed
+        final int[] codeUnits = CharTypes.getInputCodeComment();
+        while (true) {
+            int idx = _inputData.readUnsignedByte();
+            int currCode = codeUnits[idx];
+            if (currCode != 0) {
+                switch (currCode) {
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
+                    if (currCode < 0) {
+                        // Is this good enough error message?
+                        _reportInvalidCharacter(idx);
+                    }
+                }
+            }
+        }
+    }
+    
+    @Override
+    protected char _decodeEscaped() throws IOException
+    {
+        int codecParam = _inputData.readUnsignedByte();
+
+        switch (codecParam) {
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
+            return (char) codecParam;
+
+        case 'u': // and finally hex-escaped
+            break;
+
+        default:
+            return _handleUnrecognizedCharacterEscape((char) _decodeUtf8CharForError(codecParam));
+        }
+
+        // Ok, a hex escape. Need 4 characters
+        int decodedCode = 0;
+        for (int idx = 0; idx < 4; ++idx) {
+            int chars = _inputData.readUnsignedByte();
+            int hexNibble = CharTypes.charToHex(chars);
+            if (hexNibble < 0) {
+                _reportUnexpectedChar(chars, "expected a hex-digit for character escape sequence");
+            }
+            decodedCode = (decodedCode << 4) | hexNibble;
+        }
+        return (char) decodedCode;
+    }
+
+    protected int _decodeUtf8CharForError(int initialByte) throws IOException
+    {
+        int codecParam = initialByte & 0xFF;
+        if (codecParam > 0x7F) { // if >= 0, is ascii and fine as is
+            int requiredBytes;
+            
+            // Ok; if we end here, we got multi-byte combination
+            if ((codecParam & 0xE0) == 0xC0) { // 2 bytes (0x0080 - 0x07FF)
+                codecParam &= 0x1F;
+                requiredBytes = 1;
+            } else if ((codecParam & 0xF0) == 0xE0) { // 3 bytes (0x0800 - 0xFFFF)
+                codecParam &= 0x0F;
+                requiredBytes = 2;
+            } else if ((codecParam & 0xF8) == 0xF0) {
+                // 4 bytes; double-char with surrogates and all...
+                codecParam &= 0x07;
+                requiredBytes = 3;
+            } else {
+                _reportInvalidStartByte(codecParam & 0xFF);
+                requiredBytes = 1; // never gets here
+            }
+
+            int byteVal = _inputData.readUnsignedByte();
+            if ((byteVal & 0xC0) != 0x080) {
+                _reportInvalidMiddleByte(byteVal & 0xFF);
+            }
+            codecParam = (codecParam << 6) | (byteVal & 0x3F);
+            
+            if (requiredBytes > 1) { // needed == 1 means 2 bytes total
+                byteVal = _inputData.readUnsignedByte(); // 3rd byte
+                if ((byteVal & 0xC0) != 0x080) {
+                    _reportInvalidMiddleByte(byteVal & 0xFF);
+                }
+                codecParam = (codecParam << 6) | (byteVal & 0x3F);
+                if (requiredBytes > 2) { // 4 bytes? (need surrogates)
+                    byteVal = _inputData.readUnsignedByte();
+                    if ((byteVal & 0xC0) != 0x080) {
+                        _reportInvalidMiddleByte(byteVal & 0xFF);
+                    }
+                    codecParam = (codecParam << 6) | (byteVal & 0x3F);
+                }
+            }
+        }
+        return codecParam;
+    }
+
+    /*
+    /**********************************************************
+    /* Internal methods,UTF8 decoding
+    /**********************************************************
+     */
+
+    private final int decodeUtf8_2(int codecParam) throws IOException
+    {
+        int byteVal = _inputData.readUnsignedByte();
+        if ((byteVal & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(byteVal & 0xFF);
+        }
+        return ((codecParam & 0x1F) << 6) | (byteVal & 0x3F);
+    }
+
+    private final int decodeUtf8ThreeBytes(int firstByte) throws IOException
+    {
+        firstByte &= 0x0F;
+        int byteVal = _inputData.readUnsignedByte();
+        if ((byteVal & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(byteVal & 0xFF);
+        }
+        int codecParam = (firstByte << 6) | (byteVal & 0x3F);
+        byteVal = _inputData.readUnsignedByte();
+        if ((byteVal & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(byteVal & 0xFF);
+        }
+        codecParam = (codecParam << 6) | (byteVal & 0x3F);
+        return codecParam;
+    }
+
+    /**
+     * @return Character value <b>minus 0x10000</c>; this so that caller
+     *    can readily expand it to actual surrogates
+     */
+    private final int _decodeUtf8_4Bytes(int codecParam) throws IOException
+    {
+        int byteVal = _inputData.readUnsignedByte();
+        if ((byteVal & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(byteVal & 0xFF);
+        }
+        codecParam = ((codecParam & 0x07) << 6) | (byteVal & 0x3F);
+        byteVal = _inputData.readUnsignedByte();
+        if ((byteVal & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(byteVal & 0xFF);
+        }
+        codecParam = (codecParam << 6) | (byteVal & 0x3F);
+        byteVal = _inputData.readUnsignedByte();
+        if ((byteVal & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(byteVal & 0xFF);
+        }
+
+        /* note: won't change it to negative here, since caller
+         * already knows it'll need a surrogate
+         */
+        return ((codecParam << 6) | (byteVal & 0x3F)) - 0x10000;
+    }
+
+    private final void skipUtf8_2() throws IOException
+    {
+        int codecParam = _inputData.readUnsignedByte();
+        if ((codecParam & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(codecParam & 0xFF);
+        }
+    }
+
+    /* Alas, can't heavily optimize skipping, since we still have to
+     * do validity checks...
+     */
+    private final void _skipUtf8_3Bytes() throws IOException
+    {
+        //c &= 0x0F;
+        int codecParam = _inputData.readUnsignedByte();
+        if ((codecParam & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(codecParam & 0xFF);
+        }
+        codecParam = _inputData.readUnsignedByte();
+        if ((codecParam & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(codecParam & 0xFF);
+        }
+    }
+
+    private final void skipUtf8_4() throws IOException
+    {
+        int byteVal = _inputData.readUnsignedByte();
+        if ((byteVal & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(byteVal & 0xFF);
+        }
+        byteVal = _inputData.readUnsignedByte();
+        if ((byteVal & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(byteVal & 0xFF);
+        }
+        byteVal = _inputData.readUnsignedByte();
+        if ((byteVal & 0xC0) != 0x080) {
+            _reportInvalidMiddleByte(byteVal & 0xFF);
+        }
+    }
+
+    /*
+    /**********************************************************
+    /* Internal methods, error reporting
+    /**********************************************************
+     */
+
+    protected void _reportUnexpectedToken(int chars, String tokenSegment) throws IOException
+     {
+         _reportUnexpectedToken(chars, tokenSegment, "'null', 'true', 'false' or NaN");
+     }
+
+    protected void _reportUnexpectedToken(int chars, String tokenSegment, String messageText)
+        throws IOException
+     {
+         StringBuilder builder = new StringBuilder(tokenSegment);
+
+         /* Let's just try to find what appears to be the token, using
+          * regular Java identifier character rules. It's just a heuristic,
+          * nothing fancy here (nor fast).
+          */
+         while (true) {
+             char codecParam = (char) _decodeUtf8CharForError(chars);
+             if (!Character.isJavaIdentifierPart(codecParam)) {
+                 break;
+             }
+             builder.append(codecParam);
+             chars = _inputData.readUnsignedByte();
+         }
+         _reportError("Unrecognized token '"+ builder.toString()+"': was expecting "+ messageText);
+     }
+        
+    protected void _reportInvalidCharacter(int codecParam)
+        throws JsonParseException
+    {
+        // Either invalid WS or illegal UTF-8 start char
+        if (codecParam < INT_SPACE) {
+            _throwInvalidSpace(codecParam);
+        }
+        _reportInvalidStartByte(codecParam);
+    }
+
+    protected void _reportInvalidStartByte(int bitPattern)
+        throws JsonParseException
+    {
+        _reportError("Invalid UTF-8 start byte 0x"+Integer.toHexString(bitPattern));
+    }
+
+    private void _reportInvalidMiddleByte(int bitPattern)
+        throws JsonParseException
+    {
+        _reportError("Invalid UTF-8 middle byte 0x"+Integer.toHexString(bitPattern));
+    }
+
+    private static int[] growArrayBy(int[] srcArray, int additional)
+    {
+        if (srcArray == null) {
+            return new int[additional];
+        }
+        return Arrays.copyOf(srcArray, srcArray.length + additional);
+    }
+
+    /*
+    /**********************************************************
+    /* Internal methods, binary access
+    /**********************************************************
+     */
+
+    /**
+     * Efficient handling for incremental parsing of base64-encoded
+     * textual content.
+     */
+    @SuppressWarnings("resource")
+    protected final byte[] _decodeBase64ToBytes(Base64Variant base64Variant) throws IOException
+    {
+        ByteArrayBuilder byteArrayBuilder = _getByteArrayBuilder();
+
+        //main_loop:
+        while (true) {
+            // first, we'll skip preceding white space, if any
+            int chars;
+            do {
+                chars = _inputData.readUnsignedByte();
+            } while (chars <= INT_SPACE);
+            int bitCount = base64Variant.decodeBase64Char(chars);
+            if (bitCount < 0) { // reached the end, fair and square?
+                if (chars == INT_QUOTE) {
+                    return byteArrayBuilder.toByteArray();
+                }
+                bitCount = _decodeBase64Escape(base64Variant, chars, 0);
+                if (bitCount < 0) { // white space to skip
+                    continue;
+                }
+            }
+            int decodedValue = bitCount;
+            
+            // then second base64 char; can't get padding yet, nor ws
+            chars = _inputData.readUnsignedByte();
+            bitCount = base64Variant.decodeBase64Char(chars);
+            if (bitCount < 0) {
+                bitCount = _decodeBase64Escape(base64Variant, chars, 1);
+            }
+            decodedValue = (decodedValue << 6) | bitCount;
+            // third base64 char; can be padding, but not ws
+            chars = _inputData.readUnsignedByte();
+            bitCount = base64Variant.decodeBase64Char(chars);
+
+            // First branch: can get padding (-> 1 byte)
+            if (bitCount < 0) {
+                if (bitCount != Base64Variant.BASE64_VALUE_PADDING) {
+                    // could also just be 'missing'  padding
+                    if (chars == '"' && !base64Variant.usesPadding()) {
+                        decodedValue >>= 4;
+                        byteArrayBuilder.append(decodedValue);
+                        return byteArrayBuilder.toByteArray();
+                    }
+                    bitCount = _decodeBase64Escape(base64Variant, chars, 2);
+                }
+                if (bitCount == Base64Variant.BASE64_VALUE_PADDING) {
+                    chars = _inputData.readUnsignedByte();
+                    if (!base64Variant.usesPaddingChar(chars)) {
+                        throw reportInvalidBase64Char(base64Variant, chars, 3, "expected padding character '"+ base64Variant.getPaddingChar()+"'");
+                    }
+                    // Got 12 bits, only need 8, need to shift
+                    decodedValue >>= 4;
+                    byteArrayBuilder.append(decodedValue);
+                    continue;
+                }
+            }
+            // Nope, 2 or 3 bytes
+            decodedValue = (decodedValue << 6) | bitCount;
+            // fourth and last base64 char; can be padding, but not ws
+            chars = _inputData.readUnsignedByte();
+            bitCount = base64Variant.decodeBase64Char(chars);
+            if (bitCount < 0) {
+                if (bitCount != Base64Variant.BASE64_VALUE_PADDING) {
+                    // could also just be 'missing'  padding
+                    if (chars == '"' && !base64Variant.usesPadding()) {
+                        decodedValue >>= 2;
+                        byteArrayBuilder.appendTwoBytes(decodedValue);
+                        return byteArrayBuilder.toByteArray();
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
+                    byteArrayBuilder.appendTwoBytes(decodedValue);
+                    continue;
+                }
+            }
+            // otherwise, our triplet is now complete
+            decodedValue = (decodedValue << 6) | bitCount;
+            byteArrayBuilder.appendThreeBytes(decodedValue);
+        }
+    }
+
+    /*
+    /**********************************************************
+    /* Improved location updating (refactored in 2.7)
+    /**********************************************************
+     */
+
+    @Override
+    public JsonLocation getTokenLocation() {
+        return new JsonLocation(_getSourceReference(), -1L, -1L, _tokenInputRow, -1);
+    }
+
+    @Override
+    public JsonLocation getCurrentLocation() {
+        return new JsonLocation(_getSourceReference(), -1L, -1L, _currInputRow, -1);
+    }
+
+    /*
+    /**********************************************************
+    /* Internal methods, other
+    /**********************************************************
+     */
+
+    private void _closeCurrentScope(int idx) throws JsonParseException {
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
+    }
+
+    /**
+     * Helper method needed to fix [Issue#148], masking of 0x00 character
+     */
+    private final static int signExtend(int quad, int byteCount) {
+        return (byteCount == 4) ? quad : (quad | (-1 << (byteCount << 3)));
+    }
+}
diff --git a/src/test/java/com/fasterxml/jackson/core/TestVersions.java b/src/test/java/com/fasterxml/jackson/core/TestVersions.java
index 865be6f1..e1f80cf8 100644
--- a/src/test/java/com/fasterxml/jackson/core/TestVersions.java
+++ b/src/test/java/com/fasterxml/jackson/core/TestVersions.java
@@ -13,7 +13,7 @@ public class TestVersions extends com.fasterxml.jackson.core.BaseTest
     public void testCoreVersions() throws Exception
     {
         assertVersion(new JsonFactory().version());
-        ReaderBasedJsonParser jp = new ReaderBasedJsonParser(getIOContext(), 0, null, null,
+        ReaderBackedJsonParser jp = new ReaderBackedJsonParser(getIOContext(), 0, null, null,
                 CharsToNameCanonicalizer.createRoot());
         assertVersion(jp.version());
         jp.close();
diff --git a/src/test/java/com/fasterxml/jackson/core/read/TrailingCommasTest.java b/src/test/java/com/fasterxml/jackson/core/read/TrailingCommasTest.java
index 5ca9eb38..16597299 100644
--- a/src/test/java/com/fasterxml/jackson/core/read/TrailingCommasTest.java
+++ b/src/test/java/com/fasterxml/jackson/core/read/TrailingCommasTest.java
@@ -5,7 +5,7 @@ import com.fasterxml.jackson.core.JsonFactory;
 import com.fasterxml.jackson.core.JsonParser;
 import com.fasterxml.jackson.core.JsonParser.Feature;
 import com.fasterxml.jackson.core.JsonToken;
-import com.fasterxml.jackson.core.json.UTF8DataInputJsonParser;
+import com.fasterxml.jackson.core.json.UTF8InputStreamJsonParser;
 
 import org.junit.Test;
 import org.junit.runner.RunWith;
@@ -311,7 +311,7 @@ public class TrailingCommasTest extends BaseTest {
 
   private void assertEnd(JsonParser p) throws IOException {
     // Issue #325
-    if (!(p instanceof UTF8DataInputJsonParser)) {
+    if (!(p instanceof UTF8InputStreamJsonParser)) {
       JsonToken next = p.nextToken();
       assertNull("expected end of stream but found " + next, next);
     }
diff --git a/src/test/java/com/fasterxml/jackson/core/sym/SymbolTableMergingTest.java b/src/test/java/com/fasterxml/jackson/core/sym/SymbolTableMergingTest.java
index 766fada9..11417e9f 100644
--- a/src/test/java/com/fasterxml/jackson/core/sym/SymbolTableMergingTest.java
+++ b/src/test/java/com/fasterxml/jackson/core/sym/SymbolTableMergingTest.java
@@ -3,7 +3,7 @@ package com.fasterxml.jackson.core.sym;
 import java.io.IOException;
 
 import com.fasterxml.jackson.core.*;
-import com.fasterxml.jackson.core.json.ReaderBasedJsonParser;
+import com.fasterxml.jackson.core.json.ReaderBackedJsonParser;
 import com.fasterxml.jackson.core.json.UTF8StreamJsonParser;
 
 /**
@@ -106,7 +106,7 @@ public class SymbolTableMergingTest
             assertEquals(0, f.byteSymbolCount());
         } else {
             jp = f.createParser(doc);
-            assertEquals(ReaderBasedJsonParser.class, jp.getClass());
+            assertEquals(ReaderBackedJsonParser.class, jp.getClass());
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
