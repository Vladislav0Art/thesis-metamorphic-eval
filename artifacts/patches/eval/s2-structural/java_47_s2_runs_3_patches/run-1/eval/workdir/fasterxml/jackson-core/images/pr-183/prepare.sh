#!/bin/bash
set -e

cd /home/jackson-core
git reset --hard
bash /home/check_git_changes.sh
git checkout ac6d8e22847c19b2695cbd7d1f418e07a9a3dbb2

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/com/fasterxml/jackson/core/util/TextBuffer.java b/src/main/java/com/fasterxml/jackson/core/util/TextBuffer.java
index e6f1cbc5..1f34d701 100644
--- a/src/main/java/com/fasterxml/jackson/core/util/TextBuffer.java
+++ b/src/main/java/com/fasterxml/jackson/core/util/TextBuffer.java
@@ -118,56 +118,148 @@ public final class TextBuffer
     /**********************************************************
      */
 
-    public TextBuffer(BufferRecycler allocator) {
-        _allocator = allocator;
-    }
+    /*
+    /**********************************************************
+    /* Accessors for implementing public interface
+    /**********************************************************
+     */
 
-    /**
-     * Method called to indicate that the underlying buffers should now
-     * be recycled if they haven't yet been recycled. Although caller
-     * can still use this text buffer, it is not advisable to call this
-     * method if that is likely, since next time a buffer is needed,
-     * buffers need to reallocated.
-     * Note: calling this method automatically also clears contents
-     * of the buffer.
+    /*
+    /**********************************************************
+    /* Other accessors:
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Public mutators:
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Raw access, for high-performance use:
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Standard methods:
+    /**********************************************************
+     */
+
+    /*
+    /**********************************************************
+    /* Internal methods:
+    /**********************************************************
      */
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
 
     /**
-     * Method called to clear out any content text buffer may have, and
-     * initializes buffer to use non-shared data.
+     * Method called if/when we need to append content when we have been
+     * initialized to use shared buffer.
      */
-    public void resetWithEmpty()
+    private void unshare(int needExtra)
     {
-        _inputStart = -1; // indicates shared buffer not used
-        _currentSize = 0;
+        int sharedLen = _inputLen;
         _inputLen = 0;
+        char[] inputBuf = _inputBuffer;
+        _inputBuffer = null;
+        int start = _inputStart;
+        _inputStart = -1;
 
+        // Is buffer big enough, or do we need to reallocate?
+        int needed = sharedLen+needExtra;
+        if (_currentSegment == null || needed > _currentSegment.length) {
+            _currentSegment = buf(needed);
+        }
+        if (sharedLen > 0) {
+            System.arraycopy(inputBuf, start, _currentSegment, 0, sharedLen);
+        }
+        _segmentSize = 0;
+        _currentSize = sharedLen;
+    } /**
+     * Note: calling this method may not be as efficient as calling
+     * {@link #contentsAsString}, since it's not guaranteed that resulting
+     * String is cached.
+     */
+    @Override public String toString() { return contentsAsString(); } /**
+     * @return Number of characters currently stored by this collector
+     */
+    public int size() {
+        if (_inputStart >= 0) { // shared copy from input buf
+            return _inputLen;
+        }
+        if (_resultArray != null) {
+            return _resultArray.length;
+        }
+        if (_resultString != null) {
+            return _resultString.length();
+        }
+        // local segmented buffers
+        return _segmentSize + _currentSize;
+    }public void setCurrentLength(int len) { _currentSize = len; } /**
+     * @since 2.6
+     */
+    public String setCurrentAndReturn(int len) {
+        _currentSize = len;
+        // We can simplify handling here compared to full `contentsAsString()`:
+        if (_segmentSize > 0) { // longer text; call main method
+            return contentsAsString();
+        }
+        // more common case: single segment
+        int currLen = _currentSize;
+        String str = (currLen == 0) ? "" : new String(_currentSegment, 0, currLen);
+        _resultString = str;
+        return str;
+    }private char[] resultArray()
+    {
+        if (_resultString != null) { // Can take a shortcut...
+            return _resultString.toCharArray();
+        }
+        // Do we use shared array?
+        if (_inputStart >= 0) {
+            final int len = _inputLen;
+            if (len < 1) {
+                return NO_CHARS;
+            }
+            final int start = _inputStart;
+            if (start == 0) {
+                return Arrays.copyOf(_inputBuffer, len);
+            }
+            return Arrays.copyOfRange(_inputBuffer, start, start+len);
+        }
+        // nope, not shared
+        int size = size();
+        if (size < 1) {
+            return NO_CHARS;
+        }
+        int offset = 0;
+        final char[] result = carr(size);
+        if (_segments != null) {
+            for (int i = 0, len = _segments.size(); i < len; ++i) {
+                char[] curr = _segments.get(i);
+                int currLen = curr.length;
+                System.arraycopy(curr, 0, result, offset, currLen);
+                offset += currLen;
+            }
+        }
+        System.arraycopy(_currentSegment, 0, result, offset, _currentSize);
+        return result;
+    }public void resetWithString(String value)
+    {
         _inputBuffer = null;
-        _resultString = null;
+        _inputStart = -1;
+        _inputLen = 0;
+
+        _resultString = value;
         _resultArray = null;
 
-        // And then reset internal input buffers, if necessary:
         if (_hasSegments) {
             clearSegments();
         }
-    }
+        _currentSize = 0;
 
-    /**
+    } /**
      * Method called to initialize the buffer with a shared copy of data;
      * this means that buffer will just have pointers to actual data. It
      * also means that if anything is to be appended to the buffer, it
@@ -188,101 +280,65 @@ public final class TextBuffer
         if (_hasSegments) {
             clearSegments();
         }
-    }
-
-    public void resetWithCopy(char[] buf, int start, int len)
+    } /**
+     * Method called to clear out any content text buffer may have, and
+     * initializes buffer to use non-shared data.
+     */
+    public void resetWithEmpty()
     {
-        _inputBuffer = null;
         _inputStart = -1; // indicates shared buffer not used
+        _currentSize = 0;
         _inputLen = 0;
 
+        _inputBuffer = null;
         _resultString = null;
         _resultArray = null;
 
         // And then reset internal input buffers, if necessary:
         if (_hasSegments) {
             clearSegments();
-        } else if (_currentSegment == null) {
-            _currentSegment = buf(len);
         }
-        _currentSize = _segmentSize = 0;
-        append(buf, start, len);
-    }
-
-    public void resetWithString(String value)
+    }public void resetWithCopy(char[] buf, int start, int len)
     {
         _inputBuffer = null;
-        _inputStart = -1;
+        _inputStart = -1; // indicates shared buffer not used
         _inputLen = 0;
 
-        _resultString = value;
+        _resultString = null;
         _resultArray = null;
 
+        // And then reset internal input buffers, if necessary:
         if (_hasSegments) {
             clearSegments();
+        } else if (_currentSegment == null) {
+            _currentSegment = buf(len);
         }
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
         _currentSize = _segmentSize = 0;
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
+        append(buf, start, len);
+    } /**
+     * Method called to indicate that the underlying buffers should now
+     * be recycled if they haven't yet been recycled. Although caller
+     * can still use this text buffer, it is not advisable to call this
+     * method if that is likely, since next time a buffer is needed,
+     * buffers need to reallocated.
+     * Note: calling this method automatically also clears contents
+     * of the buffer.
      */
-    public int size() {
-        if (_inputStart >= 0) { // shared copy from input buf
-            return _inputLen;
-        }
-        if (_resultArray != null) {
-            return _resultArray.length;
-        }
-        if (_resultString != null) {
-            return _resultString.length();
+    public void releaseBuffers()
+    {
+        if (_allocator == null) {
+            resetWithEmpty();
+        } else {
+            if (_currentSegment != null) {
+                // First, let's get rid of all but the largest char array
+                resetWithEmpty();
+                // And then return that array
+                char[] buf = _currentSegment;
+                _currentSegment = null;
+                _allocator.releaseCharBuffer(BufferRecycler.CHAR_TEXT_BUFFER, buf);
+            }
         }
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
+    } /**
      * Method that can be used to check whether textual contents can
      * be efficiently accessed using {@link #getTextBuffer}.
      */
@@ -293,9 +349,13 @@ public final class TextBuffer
         // not if we have String as value
         if (_resultString != null) return false;
         return true;
-    }
-    
-    public char[] getTextBuffer()
+    }public int getTextOffset() {
+        /* Only shared input buffer can have non-zero offset; buffer
+         * segments start at 0, and if we have to create a combo buffer,
+         * that too will start from beginning of the buffer
+         */
+        return (_inputStart >= 0) ? _inputStart : 0;
+    }public char[] getTextBuffer()
     {
         // Are we just using shared input buffer?
         if (_inputStart >= 0) return _inputBuffer;
@@ -307,15 +367,128 @@ public final class TextBuffer
         if (!_hasSegments)  return _currentSegment;
         // Nope, need to have/create a non-segmented array and return it
         return contentsAsArray();
-    }
+    }public int getCurrentSegmentSize() { return _currentSize; }public char[] getCurrentSegment()
+    {
+        /* Since the intention of the caller is to directly add stuff into
+         * buffers, we should NOT have anything in shared buffer... ie. may
+         * need to unshare contents.
+         */
+        if (_inputStart >= 0) {
+            unshare(1);
+        } else {
+            char[] curr = _currentSegment;
+            if (curr == null) {
+                _currentSegment = buf(0);
+            } else if (_currentSize >= curr.length) {
+                // Plus, we better have room for at least one more char
+                expand(1);
+            }
+        }
+        return _currentSegment;
+    }public char[] finishCurrentSegment() {
+        if (_segments == null) {
+            _segments = new ArrayList<char[]>();
+        }
+        _hasSegments = true;
+        _segments.add(_currentSegment);
+        int oldLen = _currentSegment.length;
+        _segmentSize += oldLen;
+        _currentSize = 0;
 
-    /*
-    /**********************************************************
-    /* Other accessors:
-    /**********************************************************
+        // Let's grow segments by 50%
+        int newLen = oldLen + (oldLen >> 1);
+        if (newLen < MIN_SEGMENT_LEN) {
+            newLen = MIN_SEGMENT_LEN;
+        } else if (newLen > MAX_SEGMENT_LEN) {
+            newLen = MAX_SEGMENT_LEN;
+        }
+        char[] curr = carr(newLen);
+        _currentSegment = curr;
+        return curr;
+    } /**
+     * Method called to expand size of the current segment, to
+     * accommodate for more contiguous content. Usually only
+     * used when parsing tokens like names if even then.
      */
+    public char[] expandCurrentSegment()
+    {
+        final char[] curr = _currentSegment;
+        // Let's grow by 50% by default
+        final int len = curr.length;
+        int newLen = len + (len >> 1);
+        // but above intended maximum, slow to increase by 25%
+        if (newLen > MAX_SEGMENT_LEN) {
+            newLen = len + (len >> 2);
+        }
+        return (_currentSegment = Arrays.copyOf(curr, newLen));
+    } /**
+     * Method called to expand size of the current segment, to
+     * accommodate for more contiguous content. Usually only
+     * used when parsing tokens like names if even then.
+     *
+     * @param minSize Required minimum strength of the current segment
+     *
+     * @since 2.4.0
+     */
+    public char[] expandCurrentSegment(int minSize) {
+        char[] curr = _currentSegment;
+        if (curr.length >= minSize) return curr;
+        _currentSegment = curr = Arrays.copyOf(curr, minSize);
+        return curr;
+    } /**
+     * Method called when current segment is full, to allocate new
+     * segment.
+     */
+    private void expand(int minNewSegmentSize)
+    {
+        // First, let's move current segment to segment list:
+        if (_segments == null) {
+            _segments = new ArrayList<char[]>();
+        }
+        char[] curr = _currentSegment;
+        _hasSegments = true;
+        _segments.add(curr);
+        _segmentSize += curr.length;
+        _currentSize = 0;
+        int oldLen = curr.length;
 
-    public String contentsAsString()
+        // Let's grow segments by 50% minimum
+        int newLen = oldLen + (oldLen >> 1);
+        if (newLen < MIN_SEGMENT_LEN) {
+            newLen = MIN_SEGMENT_LEN;
+        } else if (newLen > MAX_SEGMENT_LEN) {
+            newLen = MAX_SEGMENT_LEN;
+        }
+        _currentSegment = carr(newLen);
+    } /**
+     * Method called to make sure that buffer is not using shared input
+     * buffer; if it is, it will copy such contents to private buffer.
+     */
+    public void ensureNotShared() {
+        if (_inputStart >= 0) {
+            unshare(16);
+        }
+    }public char[] emptyAndGetCurrentSegment()
+    {
+        // inlined 'resetWithEmpty()'
+        _inputStart = -1; // indicates shared buffer not used
+        _currentSize = 0;
+        _inputLen = 0;
+
+        _inputBuffer = null;
+        _resultString = null;
+        _resultArray = null;
+
+        // And then reset internal input buffers, if necessary:
+        if (_hasSegments) {
+            clearSegments();
+        }
+        char[] curr = _currentSegment;
+        if (curr == null) {
+            _currentSegment = curr = buf(0);
+        }
+        return curr;
+    }public String contentsAsString()
     {
         if (_resultString == null) {
             // Has array been requested? Can make a shortcut, if so:
@@ -332,7 +505,7 @@ public final class TextBuffer
                     // But first, let's see if we have just one buffer
                     int segLen = _segmentSize;
                     int currLen = _currentSize;
-                    
+
                     if (segLen == 0) { // yup
                         _resultString = (currLen == 0) ? "" : new String(_currentSegment, 0, currLen);
                     } else { // no, need to combine
@@ -352,17 +525,13 @@ public final class TextBuffer
             }
         }
         return _resultString;
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
+    } /**
+     * Convenience method for converting contents of the buffer
+     * into a Double value.
+     */
+    public double contentsAsDouble() throws NumberFormatException {
+        return NumberInput.parseDouble(contentsAsString());
+    } /**
      * Convenience method for converting contents of the buffer
      * into a {@link BigDecimal}.
      */
@@ -370,45 +539,47 @@ public final class TextBuffer
     {
         // Already got a pre-cut array?
         if (_resultArray != null) {
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
+            return NumberInput.parseBigDecimal(_resultArray);
+        }
+        // Or a shared buffer?
+        if ((_inputStart >= 0) && (_inputBuffer != null)) {
+            return NumberInput.parseBigDecimal(_inputBuffer, _inputStart, _inputLen);
+        }
+        // Or if not, just a single buffer (the usual case)
+        if ((_segmentSize == 0) && (_currentSegment != null)) {
+            return NumberInput.parseBigDecimal(_currentSegment, 0, _currentSize);
+        }
+        // If not, let's just get it aggregated...
+        return NumberInput.parseBigDecimal(contentsAsArray());
+    }public char[] contentsAsArray() {
+        char[] result = _resultArray;
+        if (result == null) {
+            _resultArray = result = resultArray();
+        }
+        return result;
+    }private void clearSegments()
+    {
+        _hasSegments = false;
+        /* Let's start using _last_ segment from list; for one, it's
+         * the biggest one, and it's also most likely to be cached
+         */
+        /* 28-Aug-2009, tatu: Actually, the current segment should
+         *   be the biggest one, already
+         */
+        //_currentSegment = _segments.get(_segments.size() - 1);
+        _segments.clear();
+        _currentSize = _segmentSize = 0;
+    }private char[] carr(int len) { return new char[len]; } /**
+     * Helper method used to find a buffer to use, ideally one
+     * recycled earlier.
      */
-    public void ensureNotShared() {
-        if (_inputStart >= 0) {
-            unshare(16);
+    private char[] buf(int needed)
+    {
+        if (_allocator != null) {
+            return _allocator.allocCharBuffer(BufferRecycler.CHAR_TEXT_BUFFER, needed);
         }
-    }
-
-    public void append(char c) {
+        return new char[Math.max(needed, MIN_SEGMENT_LEN)];
+    }public void append(char c) {
         // Using shared buffer so far?
         if (_inputStart >= 0) {
             unshare(16);
@@ -422,9 +593,7 @@ public final class TextBuffer
             curr = _currentSegment;
         }
         curr[_currentSize++] = c;
-    }
-
-    public void append(char[] c, int start, int len)
+    }public void append(char[] c, int start, int len)
     {
         // Can't append to shared buf (sanity check)
         if (_inputStart >= 0) {
@@ -436,7 +605,7 @@ public final class TextBuffer
         // Room in current segment?
         char[] curr = _currentSegment;
         int max = curr.length - _currentSize;
-            
+
         if (max >= len) {
             System.arraycopy(c, start, curr, _currentSize, len);
             _currentSize += len;
@@ -460,9 +629,7 @@ public final class TextBuffer
             start += amount;
             len -= amount;
         } while (len > 0);
-    }
-
-    public void append(String str, int offset, int len)
+    }public void append(String str, int offset, int len)
     {
         // Can't append to shared buf (sanity check)
         if (_inputStart >= 0) {
@@ -497,237 +664,6 @@ public final class TextBuffer
             offset += amount;
             len -= amount;
         } while (len > 0);
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
+    }public TextBuffer(BufferRecycler allocator) {
+        _allocator = allocator;
+    }}

EOF_METAMORPHIC_PATCH
git apply /home/metamorphic_base.patch
git add -A && git -c user.email='mswe-agent@metamorphic.py' -c user.name='metamorphic-transformation-patch' commit -m 'Apply `metamorphic_base_patch` transformation to base commit'


bash /home/check_git_changes.sh

file="/home/jackson-core/pom.xml"
old_version="2.15.0-rc2-SNAPSHOT"
new_version="2.15.5-SNAPSHOT"
sed -i "s/$old_version/$new_version/g" "$file"

mvn clean test -Dmaven.test.skip=false -DfailIfNoTests=false || true
