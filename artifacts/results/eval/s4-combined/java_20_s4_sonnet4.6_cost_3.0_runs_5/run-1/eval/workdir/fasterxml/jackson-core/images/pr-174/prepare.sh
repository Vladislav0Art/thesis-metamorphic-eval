#!/bin/bash
set -e

cd /home/jackson-core
git reset --hard
bash /home/check_git_changes.sh
git checkout b0f217a849703a453952f93b5999c557c201a4be

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/com/fasterxml/jackson/core/JsonPointer.java b/src/main/java/com/fasterxml/jackson/core/JsonPointerPath.java
similarity index 51%
rename from src/main/java/com/fasterxml/jackson/core/JsonPointer.java
rename to src/main/java/com/fasterxml/jackson/core/JsonPointerPath.java
index ff251034..417599a3 100644
--- a/src/main/java/com/fasterxml/jackson/core/JsonPointer.java
+++ b/src/main/java/com/fasterxml/jackson/core/JsonPointerPath.java
@@ -17,7 +17,7 @@ import com.fasterxml.jackson.core.io.NumberInput;
  * 
  * @since 2.3
  */
-public class JsonPointer
+public class JsonPointerPath
 {
     protected final static int NO_SLASH = -1;
 
@@ -25,20 +25,20 @@ public class JsonPointer
      * Marker instance used to represent segment that matches current
      * node or position.
      */
-    protected final static JsonPointer EMPTY = new JsonPointer();
+    protected final static JsonPointerPath EMPTY = new JsonPointerPath();
     
     /**
      * Reference to rest of the pointer beyond currently matching
      * segment (if any); null if this pointer refers to a matching
      * segment.
      */
-    protected final JsonPointer _nextSegment;
+    protected final JsonPointerPath _nextSegment;
 
     /**
      * Reference form currently matching segment (if any) to node
      * before leaf.
      */
-    protected final JsonPointer _headSegment;
+    protected final JsonPointerPath _headSegment;
 
     /**
      * We will retain representation of the pointer, as a String,
@@ -56,64 +56,12 @@ public class JsonPointer
     /**********************************************************
      */
     
-    /**
-     * Constructor used for creating "empty" instance, used to represent
-     * state that matches current node.
-     */
-    protected JsonPointer() {
-        _nextSegment = null;
-        _headSegment = null;
-        _matchingPropertyName = "";
-        _matchingElementIndex = -1;
-        _asString = "";
-    }
-
-    /**
-     * Constructor used for creating non-empty Segments
-     */
-    protected JsonPointer(String fullString, String segment, JsonPointer next, JsonPointer head) {
-        _asString = fullString;
-        _nextSegment = next;
-        _headSegment = head;
-        // Ok; may always be a property
-        _matchingPropertyName = segment;
-        _matchingElementIndex = _parseIndex(segment);
-    }
-    
     /*
     /**********************************************************
     /* Factory methods
     /**********************************************************
      */
     
-    /**
-     * Factory method that parses given input and construct matching pointer
-     * instance, if it represents a valid JSON Pointer: if not, a
-     * {@link IllegalArgumentException} is thrown.
-     * 
-     * @throws IllegalArgumentException Thrown if the input does not present a valid JSON Pointer
-     *   expression: currently the only such expression is one that does NOT start with
-     *   a slash ('/').
-     */
-    public static JsonPointer compile(String input) throws IllegalArgumentException
-    {
-        // First quick checks for well-known 'empty' pointer
-        if ((input == null) || input.length() == 0) {
-            return EMPTY;
-        }
-        // And then quick validity check:
-        if (input.charAt(0) != '/') {
-            throw new IllegalArgumentException("Invalid input: JSON Pointer expression must start with '/': "+"\""+input+"\"");
-        }
-        return _parseTailAndHead(input);
-    }
-
-    /**
-     * Alias for {@link #compile}; added to make instances automatically
-     * deserializable by Jackson databind.
-     */
-    public static JsonPointer valueOf(String input) { return compile(input); }
-
     /* Factory method that composes a pointer instance, given a set
      * of 'raw' segments: raw meaning that no processing will be done,
      * no escaping may is present.
@@ -142,177 +90,193 @@ public class JsonPointer
     /**********************************************************
      */
 
-    public boolean matches() { return _nextSegment == null; }
-    public String getMatchingProperty() { return _matchingPropertyName; }
-    public int getMatchingIndex() { return _matchingElementIndex; }
-    public boolean mayMatchProperty() { return _matchingPropertyName != null; }
-    public boolean mayMatchElement() { return _matchingElementIndex >= 0; }
-
-    /**
-     * Method that may be called to see if the pointer would match property
-     * (of a JSON Object) with given name.
-     * 
-     * @since 2.5
-     */
-    public boolean matchesProperty(String name) {
-        return (_nextSegment != null) && _matchingPropertyName.equals(name);
-    }
-    
-    public JsonPointer matchProperty(String name) {
-        if (_nextSegment == null || !_matchingPropertyName.equals(name)) {
-            return null;
-        }
-        return _nextSegment;
-    }
-
-    /**
-     * Method that may be called to see if the pointer would match
-     * array element (of a JSON Array) with given index.
-     * 
-     * @since 2.5
-     */
-    public boolean matchesElement(int index) {
-        return (index == _matchingElementIndex) && (index >= 0);
-    }
-
-    /**
-     * Accessor for getting a "sub-pointer", instance where current segment
-     * has been removed and pointer includes rest of segments.
-     * For matching state, will return null.
-     */
-    public JsonPointer tail() {
-        return _nextSegment;
-    }
-
-    /**
-     * Accessor for getting a "pointer", instance from current segment to
-     * segment before segment leaf. For root pointer, will return null.
-     *
-     * @since 2.5
-     */
-    public JsonPointer head() {
-        return _headSegment;
-    }
-
     /*
     /**********************************************************
     /* Standard method overrides
     /**********************************************************
      */
 
-    @Override public String toString() { return _asString; }
-    @Override public int hashCode() { return _asString.hashCode(); }
-
-    @Override public boolean equals(Object o) {
-        if (o == this) return true;
-        if (o == null) return false;
-        if (!(o instanceof JsonPointer)) return false;
-        return _asString.equals(((JsonPointer) o)._asString);
-    }
-    
     /*
     /**********************************************************
     /* Internal methods
     /**********************************************************
      */
 
-    private final static int _parseIndex(String str) {
-        final int len = str.length();
-        // [Issue#133]: beware of super long indexes; assume we never
-        // have arrays over 2 billion entries so ints are fine.
-        if (len == 0 || len > 10) {
-            return -1;
-        }
-        for (int i = 0; i < len; ++i) {
-            char c = str.charAt(i);
-            if (c > '9' || c < '0') {
-                return -1;
-            }
-        }
-        if (len == 10) {
-            long l = NumberInput.parseLong(str);
-            if (l > Integer.MAX_VALUE) {
-                return -1;
-            }
-        }
-        return NumberInput.parseInt(str);
-    }
-    
-    protected static JsonPointer _parseTailAndHead(String input) {
-        final int end = input.length();
+    @Override public String toString() { return _asString; }protected static JsonPointerPath parseTailAndHead(String sourceText) {
+        final int tailIndex = sourceText.length();
 
-        int lastSlash = input.lastIndexOf('/');
+        int slashIndex = sourceText.lastIndexOf('/');
 
         // first char is the contextual slash, skip
-        for (int i = 1; i < end; ) {
-            char c = input.charAt(i);
-            if (c == '/') { // common case, got a segment
-                if(i == NO_SLASH) {
-                    return new JsonPointer(input, input.substring(1, i),
-                            _parseTailAndHead(input.substring(i)), EMPTY);
+        for (int idx = 1; idx < tailIndex; ) {
+            char ch = sourceText.charAt(idx);
+            if (ch == '/') { // common case, got a segment
+                if(idx == NO_SLASH) {
+                    return new JsonPointerPath(sourceText, sourceText.substring(1, idx),
+                            parseTailAndHead(sourceText.substring(idx)), EMPTY);
                 } else {
-                    return new JsonPointer(input, input.substring(1, i),
-                            _parseTailAndHead(input.substring(i)), compile(input.substring(0, lastSlash)));
+                    return new JsonPointerPath(sourceText, sourceText.substring(1, idx),
+                            parseTailAndHead(sourceText.substring(idx)), parse(sourceText.substring(0, slashIndex)));
                 }
             }
-            ++i;
+            ++idx;
             // quoting is different; offline this case
-            if (c == '~' && i < end) { // possibly, quote
-                return _parseQuotedTailAndHead(input, i);
+            if (ch == '~' && idx < tailIndex) { // possibly, quote
+                return _parseQuotedTailAndHeadSegments(sourceText, idx);
             }
             // otherwise, loop on
         }
         // end of the road, no escapes
-        return new JsonPointer(input, input.substring(1), EMPTY, EMPTY);
-    }
-
-    /**
+        return new JsonPointerPath(sourceText, sourceText.substring(1), EMPTY, EMPTY);
+    }private final static int parseIndex(String text) {
+        final int length = text.length();
+        // [Issue#133]: beware of super long indexes; assume we never
+        // have arrays over 2 billion entries so ints are fine.
+        if (length == 0 || length > 10) {
+            return -1;
+        }
+        for (int idx = 0; idx < length; ++idx) {
+            char ch = text.charAt(idx);
+            if (ch > '9' || ch < '0') {
+                return -1;
+            }
+        }
+        if (length == 10) {
+            long longValue = NumberInput.parseLong(text);
+            if (longValue > Integer.MAX_VALUE) {
+                return -1;
+            }
+        }
+        return NumberInput.parseInt(text);
+    } /**
+     * Factory method that parses given input and construct matching pointer
+     * instance, if it represents a valid JSON Pointer: if not, a
+     * {@link IllegalArgumentException} is thrown.
+     *
+     * @throws IllegalArgumentException Thrown if the input does not present a valid JSON Pointer
+     *   expression: currently the only such expression is one that does NOT start with
+     *   a slash ('/').
+     */
+    public static JsonPointerPath parse(String sourceText) throws IllegalArgumentException
+    {
+        // First quick checks for well-known 'empty' pointer
+        if ((sourceText == null) || sourceText.length() == 0) {
+            return EMPTY;
+        }
+        // And then quick validity check:
+        if (sourceText.charAt(0) != '/') {
+            throw new IllegalArgumentException("Invalid input: JSON Pointer expression must start with '/': "+"\""+ sourceText +"\"");
+        }
+        return parseTailAndHead(sourceText);
+    } /**
+     * Alias for {@link #parse}; added to make instances automatically
+     * deserializable by Jackson databind.
+     */
+    public static JsonPointerPath of(String sourceText) { return parse(sourceText); } /**
+     * Accessor for getting a "sub-pointer", instance where current segment
+     * has been removed and pointer includes rest of segments.
+     * For matching state, will return null.
+     */
+    public JsonPointerPath nextSegment() {
+        return _nextSegment;
+    } /**
+     * Method that may be called to see if the pointer would match property
+     * (of a JSON Object) with given name.
+     *
+     * @since 2.5
+     */
+    public boolean matchesPropertyName(String property) {
+        return (_nextSegment != null) && _matchingPropertyName.equals(property);
+    }public boolean matchesExactly() { return _nextSegment == null; } /**
+     * Method that may be called to see if the pointer would match
+     * array element (of a JSON Array) with given index.
+     *
+     * @since 2.5
+     */
+    public boolean isMatchingElement(int idx) {
+        return (idx == _matchingElementIndex) && (idx >= 0);
+    }@Override public int hashCode() { return _asString.hashCode(); }public boolean hasMatchingPropertyName() { return _matchingPropertyName != null; }public boolean hasMatchingElement() { return _matchingElementIndex >= 0; }public JsonPointerPath getMatchingPropertySegment(String property) {
+        if (_nextSegment == null || !_matchingPropertyName.equals(property)) {
+            return null;
+        }
+        return _nextSegment;
+    }public String getMatchingProperty() { return _matchingPropertyName; }public int getMatchingIndex() { return _matchingElementIndex; } /**
+     * Accessor for getting a "pointer", instance from current segment to
+     * segment before segment leaf. For root pointer, will return null.
+     *
+     * @since 2.5
+     */
+    public JsonPointerPath getHead() {
+        return _headSegment;
+    }@Override public boolean equals(Object other) {
+        if (other == this) return true;
+        if (other == null) return false;
+        if (!(other instanceof JsonPointerPath)) return false;
+        return _asString.equals(((JsonPointerPath) other)._asString);
+    }private static void appendEscapeSequence(StringBuilder builder, char ch) {
+        if (ch == '0') {
+            ch = '~';
+        } else if (ch == '1') {
+            ch = '/';
+        } else {
+            builder.append('~');
+        }
+        builder.append(ch);
+    } /**
      * Method called to parse tail of pointer path, when a potentially
      * escaped character has been seen.
-     * 
-     * @param input Full input for the tail being parsed
-     * @param i Offset to character after tilde
+     *
+     * @param sourceText Full input for the tail being parsed
+     * @param idx Offset to character after tilde
      */
-    protected static JsonPointer _parseQuotedTailAndHead(String input, int i) {
-        final int end = input.length();
-        StringBuilder sb = new StringBuilder(Math.max(16, end));
-        if (i > 2) {
-            sb.append(input, 1, i-1);
+    protected static JsonPointerPath _parseQuotedTailAndHeadSegments(String sourceText, int idx) {
+        final int tailIndex = sourceText.length();
+        StringBuilder builder = new StringBuilder(Math.max(16, tailIndex));
+        if (idx > 2) {
+            builder.append(sourceText, 1, idx -1);
         }
-        _appendEscape(sb, input.charAt(i++));
+        appendEscapeSequence(builder, sourceText.charAt(idx++));
 
-        int lastSlash = input.lastIndexOf('/');
+        int slashIndex = sourceText.lastIndexOf('/');
 
-        while (i < end) {
-            char c = input.charAt(i);
-            if (c == '/') { // end is nigh!
-                if(i == NO_SLASH) {
-                    return new JsonPointer(input, sb.toString(),
-                            _parseTailAndHead(input.substring(i)), EMPTY);
+        while (idx < tailIndex) {
+            char ch = sourceText.charAt(idx);
+            if (ch == '/') { // end is nigh!
+                if(idx == NO_SLASH) {
+                    return new JsonPointerPath(sourceText, builder.toString(),
+                            parseTailAndHead(sourceText.substring(idx)), EMPTY);
                 } else {
-                    return new JsonPointer(input, sb.toString(),
-                            _parseTailAndHead(input.substring(i)), compile(input.substring(0, lastSlash)));
+                    return new JsonPointerPath(sourceText, builder.toString(),
+                            parseTailAndHead(sourceText.substring(idx)), parse(sourceText.substring(0, slashIndex)));
                 }
             }
-            ++i;
-            if (c == '~' && i < end) {
-                _appendEscape(sb, input.charAt(i++));
+            ++idx;
+            if (ch == '~' && idx < tailIndex) {
+                appendEscapeSequence(builder, sourceText.charAt(idx++));
                 continue;
             }
-            sb.append(c);
+            builder.append(ch);
         }
         // end of the road, last segment
-        return new JsonPointer(input, sb.toString(), EMPTY, EMPTY);
-    }
-    
-    private static void _appendEscape(StringBuilder sb, char c) {
-        if (c == '0') {
-            c = '~';
-        } else if (c == '1') {
-            c = '/';
-        } else {
-            sb.append('~');
-        }
-        sb.append(c);
-    }
-}
+        return new JsonPointerPath(sourceText, builder.toString(), EMPTY, EMPTY);
+    } /**
+     * Constructor used for creating "empty" instance, used to represent
+     * state that matches current node.
+     */
+    protected JsonPointerPath() {
+        _nextSegment = null;
+        _headSegment = null;
+        _matchingPropertyName = "";
+        _matchingElementIndex = -1;
+        _asString = "";
+    } /**
+     * Constructor used for creating non-empty Segments
+     */
+    protected JsonPointerPath(String completeText, String pathPart, JsonPointerPath followingPath, JsonPointerPath leadingPath) {
+        _asString = completeText;
+        _nextSegment = followingPath;
+        _headSegment = leadingPath;
+        // Ok; may always be a property
+        _matchingPropertyName = pathPart;
+        _matchingElementIndex = parseIndex(pathPart);
+    }}
diff --git a/src/main/java/com/fasterxml/jackson/core/TreeNode.java b/src/main/java/com/fasterxml/jackson/core/TreeNode.java
index 8d8f8d7b..ec455db0 100644
--- a/src/main/java/com/fasterxml/jackson/core/TreeNode.java
+++ b/src/main/java/com/fasterxml/jackson/core/TreeNode.java
@@ -227,7 +227,7 @@ public interface TreeNode
      * 
      * @since 2.3
      */
-    TreeNode at(JsonPointer ptr);
+    TreeNode at(JsonPointerPath ptr);
 
     /**
      * Convenience method that is functionally equivalent to:
@@ -236,10 +236,10 @@ public interface TreeNode
      *</pre>
      *<p>
      * Note that if the same expression is used often, it is preferable to construct
-     * {@link JsonPointer} instance once and reuse it: this method will not perform
+     * {@link JsonPointerPath} instance once and reuse it: this method will not perform
      * any caching of compiled expressions.
      * 
-     * @param jsonPointerExpression Expression to compile as a {@link JsonPointer}
+     * @param jsonPointerExpression Expression to compile as a {@link JsonPointerPath}
      *   instance
      * 
      * @return Node that matches given JSON Pointer: if no match exists,
diff --git a/src/test/java/com/fasterxml/jackson/core/TestJsonPointer.java b/src/test/java/com/fasterxml/jackson/core/TestJsonPointer.java
index 9ef13aa7..7874c474 100644
--- a/src/test/java/com/fasterxml/jackson/core/TestJsonPointer.java
+++ b/src/test/java/com/fasterxml/jackson/core/TestJsonPointer.java
@@ -7,74 +7,74 @@ public class TestJsonPointer extends BaseTest
     {
         final String INPUT = "/Image/15/name";
 
-        JsonPointer ptr = JsonPointer.compile(INPUT);
-        assertFalse(ptr.matches());
+        JsonPointerPath ptr = JsonPointerPath.parse(INPUT);
+        assertFalse(ptr.matchesExactly());
         assertEquals(-1, ptr.getMatchingIndex());
         assertEquals("Image", ptr.getMatchingProperty());
-        assertEquals("/Image/15", ptr.head().toString());
+        assertEquals("/Image/15", ptr.getHead().toString());
         assertEquals(INPUT, ptr.toString());
 
-        ptr = ptr.tail();
+        ptr = ptr.nextSegment();
         assertNotNull(ptr);
-        assertFalse(ptr.matches());
+        assertFalse(ptr.matchesExactly());
         assertEquals(15, ptr.getMatchingIndex());
         assertEquals("15", ptr.getMatchingProperty());
-        assertEquals("/15", ptr.head().toString());
+        assertEquals("/15", ptr.getHead().toString());
         assertEquals("/15/name", ptr.toString());
 
-        ptr = ptr.tail();
+        ptr = ptr.nextSegment();
         assertNotNull(ptr);
-        assertFalse(ptr.matches());
+        assertFalse(ptr.matchesExactly());
         assertEquals(-1, ptr.getMatchingIndex());
         assertEquals("name", ptr.getMatchingProperty());
         assertEquals("/name", ptr.toString());
-        assertEquals("", ptr.head().toString());
+        assertEquals("", ptr.getHead().toString());
 
         // done!
-        ptr = ptr.tail();
-        assertTrue(ptr.matches());
-        assertNull(ptr.tail());
+        ptr = ptr.nextSegment();
+        assertTrue(ptr.matchesExactly());
+        assertNull(ptr.nextSegment());
         assertEquals("", ptr.getMatchingProperty());
         assertEquals(-1, ptr.getMatchingIndex());
     }
 
     public void testWonkyNumber173() throws Exception
     {
-        JsonPointer ptr = JsonPointer.compile("/1e0");
-        assertFalse(ptr.matches());
+        JsonPointerPath ptr = JsonPointerPath.parse("/1e0");
+        assertFalse(ptr.matchesExactly());
     }
     
     public void testQuotedPath() throws Exception
     {
         final String INPUT = "/w~1out/til~0de/a~1b";
 
-        JsonPointer ptr = JsonPointer.compile(INPUT);
-        assertFalse(ptr.matches());
+        JsonPointerPath ptr = JsonPointerPath.parse(INPUT);
+        assertFalse(ptr.matchesExactly());
         assertEquals(-1, ptr.getMatchingIndex());
         assertEquals("w/out", ptr.getMatchingProperty());
-        assertEquals("/w~1out/til~0de", ptr.head().toString());
+        assertEquals("/w~1out/til~0de", ptr.getHead().toString());
         assertEquals(INPUT, ptr.toString());
 
-        ptr = ptr.tail();
+        ptr = ptr.nextSegment();
         assertNotNull(ptr);
-        assertFalse(ptr.matches());
+        assertFalse(ptr.matchesExactly());
         assertEquals(-1, ptr.getMatchingIndex());
         assertEquals("til~de", ptr.getMatchingProperty());
-        assertEquals("/til~0de", ptr.head().toString());
+        assertEquals("/til~0de", ptr.getHead().toString());
         assertEquals("/til~0de/a~1b", ptr.toString());
 
-        ptr = ptr.tail();
+        ptr = ptr.nextSegment();
         assertNotNull(ptr);
-        assertFalse(ptr.matches());
+        assertFalse(ptr.matchesExactly());
         assertEquals(-1, ptr.getMatchingIndex());
         assertEquals("a/b", ptr.getMatchingProperty());
         assertEquals("/a~1b", ptr.toString());
-        assertEquals("", ptr.head().toString());
+        assertEquals("", ptr.getHead().toString());
 
         // done!
-        ptr = ptr.tail();
-        assertTrue(ptr.matches());
-        assertNull(ptr.tail());
+        ptr = ptr.nextSegment();
+        assertTrue(ptr.matchesExactly());
+        assertNull(ptr.nextSegment());
     }
 
     // [Issue#133]
@@ -84,13 +84,13 @@ public class TestJsonPointer extends BaseTest
         
         final String INPUT = "/User/"+LONG_ID;
 
-        JsonPointer ptr = JsonPointer.compile(INPUT);
+        JsonPointerPath ptr = JsonPointerPath.parse(INPUT);
         assertEquals("User", ptr.getMatchingProperty());
         assertEquals(INPUT, ptr.toString());
 
-        ptr = ptr.tail();
+        ptr = ptr.nextSegment();
         assertNotNull(ptr);
-        assertFalse(ptr.matches());
+        assertFalse(ptr.matchesExactly());
         /* 14-Mar-2014, tatu: We do not support array indexes beyond 32-bit
          *    range; can still match textually of course.
          */
@@ -98,8 +98,8 @@ public class TestJsonPointer extends BaseTest
         assertEquals(String.valueOf(LONG_ID), ptr.getMatchingProperty());
 
         // done!
-        ptr = ptr.tail();
-        assertTrue(ptr.matches());
-        assertNull(ptr.tail());
+        ptr = ptr.nextSegment();
+        assertTrue(ptr.matchesExactly());
+        assertNull(ptr.nextSegment());
     }
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
