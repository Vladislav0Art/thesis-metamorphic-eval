#!/bin/bash
set -e

cd /home/jackson-core
git reset --hard
bash /home/check_git_changes.sh
git checkout b0f217a849703a453952f93b5999c557c201a4be

# apply metamorphic patch (if present)
cat > /home/metamorphic_base.patch << 'EOF_METAMORPHIC_PATCH'
diff --git a/src/main/java/com/fasterxml/jackson/core/JsonPointer.java b/src/main/java/com/fasterxml/jackson/core/JsonPointerExpression.java
similarity index 53%
rename from src/main/java/com/fasterxml/jackson/core/JsonPointer.java
rename to src/main/java/com/fasterxml/jackson/core/JsonPointerExpression.java
index ff251034..4ec5b4c2 100644
--- a/src/main/java/com/fasterxml/jackson/core/JsonPointer.java
+++ b/src/main/java/com/fasterxml/jackson/core/JsonPointerExpression.java
@@ -17,7 +17,7 @@ import com.fasterxml.jackson.core.io.NumberInput;
  * 
  * @since 2.3
  */
-public class JsonPointer
+public class JsonPointerExpression
 {
     protected final static int NO_SLASH = -1;
 
@@ -25,20 +25,20 @@ public class JsonPointer
      * Marker instance used to represent segment that matches current
      * node or position.
      */
-    protected final static JsonPointer EMPTY = new JsonPointer();
+    protected final static JsonPointerExpression EMPTY = new JsonPointerExpression();
     
     /**
      * Reference to rest of the pointer beyond currently matching
      * segment (if any); null if this pointer refers to a matching
      * segment.
      */
-    protected final JsonPointer _nextSegment;
+    protected final JsonPointerExpression _nextSegment;
 
     /**
      * Reference form currently matching segment (if any) to node
      * before leaf.
      */
-    protected final JsonPointer _headSegment;
+    protected final JsonPointerExpression _headSegment;
 
     /**
      * We will retain representation of the pointer, as a String,
@@ -60,7 +60,7 @@ public class JsonPointer
      * Constructor used for creating "empty" instance, used to represent
      * state that matches current node.
      */
-    protected JsonPointer() {
+    protected JsonPointerExpression() {
         _nextSegment = null;
         _headSegment = null;
         _matchingPropertyName = "";
@@ -71,13 +71,13 @@ public class JsonPointer
     /**
      * Constructor used for creating non-empty Segments
      */
-    protected JsonPointer(String fullString, String segment, JsonPointer next, JsonPointer head) {
-        _asString = fullString;
-        _nextSegment = next;
-        _headSegment = head;
+    protected JsonPointerExpression(String sourceString, String pathPart, JsonPointerExpression followingExpression, JsonPointerExpression firstExpression) {
+        _asString = sourceString;
+        _nextSegment = followingExpression;
+        _headSegment = firstExpression;
         // Ok; may always be a property
-        _matchingPropertyName = segment;
-        _matchingElementIndex = _parseIndex(segment);
+        _matchingPropertyName = pathPart;
+        _matchingElementIndex = parseIndex(pathPart);
     }
     
     /*
@@ -95,24 +95,24 @@ public class JsonPointer
      *   expression: currently the only such expression is one that does NOT start with
      *   a slash ('/').
      */
-    public static JsonPointer compile(String input) throws IllegalArgumentException
+    public static JsonPointerExpression compilePointer(String pointerText) throws IllegalArgumentException
     {
         // First quick checks for well-known 'empty' pointer
-        if ((input == null) || input.length() == 0) {
+        if ((pointerText == null) || pointerText.length() == 0) {
             return EMPTY;
         }
         // And then quick validity check:
-        if (input.charAt(0) != '/') {
-            throw new IllegalArgumentException("Invalid input: JSON Pointer expression must start with '/': "+"\""+input+"\"");
+        if (pointerText.charAt(0) != '/') {
+            throw new IllegalArgumentException("Invalid input: JSON Pointer expression must start with '/': "+"\""+ pointerText +"\"");
         }
-        return _parseTailAndHead(input);
+        return parseTailAndHead(pointerText);
     }
 
     /**
-     * Alias for {@link #compile}; added to make instances automatically
+     * Alias for {@link #compilePointer}; added to make instances automatically
      * deserializable by Jackson databind.
      */
-    public static JsonPointer valueOf(String input) { return compile(input); }
+    public static JsonPointerExpression of(String pointerText) { return compilePointer(pointerText); }
 
     /* Factory method that composes a pointer instance, given a set
      * of 'raw' segments: raw meaning that no processing will be done,
@@ -142,11 +142,11 @@ public class JsonPointer
     /**********************************************************
      */
 
-    public boolean matches() { return _nextSegment == null; }
+    public boolean matchesExactly() { return _nextSegment == null; }
     public String getMatchingProperty() { return _matchingPropertyName; }
     public int getMatchingIndex() { return _matchingElementIndex; }
-    public boolean mayMatchProperty() { return _matchingPropertyName != null; }
-    public boolean mayMatchElement() { return _matchingElementIndex >= 0; }
+    public boolean hasMatchingProperty() { return _matchingPropertyName != null; }
+    public boolean hasMatchingElement() { return _matchingElementIndex >= 0; }
 
     /**
      * Method that may be called to see if the pointer would match property
@@ -154,12 +154,12 @@ public class JsonPointer
      * 
      * @since 2.5
      */
-    public boolean matchesProperty(String name) {
-        return (_nextSegment != null) && _matchingPropertyName.equals(name);
+    public boolean matchesPropertyName(String propertyKey) {
+        return (_nextSegment != null) && _matchingPropertyName.equals(propertyKey);
     }
     
-    public JsonPointer matchProperty(String name) {
-        if (_nextSegment == null || !_matchingPropertyName.equals(name)) {
+    public JsonPointerExpression getMatchingPropertySegment(String propertyKey) {
+        if (_nextSegment == null || !_matchingPropertyName.equals(propertyKey)) {
             return null;
         }
         return _nextSegment;
@@ -171,8 +171,8 @@ public class JsonPointer
      * 
      * @since 2.5
      */
-    public boolean matchesElement(int index) {
-        return (index == _matchingElementIndex) && (index >= 0);
+    public boolean isMatchingElement(int position) {
+        return (position == _matchingElementIndex) && (position >= 0);
     }
 
     /**
@@ -180,7 +180,7 @@ public class JsonPointer
      * has been removed and pointer includes rest of segments.
      * For matching state, will return null.
      */
-    public JsonPointer tail() {
+    public JsonPointerExpression nextSegment() {
         return _nextSegment;
     }
 
@@ -190,7 +190,7 @@ public class JsonPointer
      *
      * @since 2.5
      */
-    public JsonPointer head() {
+    public JsonPointerExpression headSegment() {
         return _headSegment;
     }
 
@@ -203,11 +203,11 @@ public class JsonPointer
     @Override public String toString() { return _asString; }
     @Override public int hashCode() { return _asString.hashCode(); }
 
-    @Override public boolean equals(Object o) {
-        if (o == this) return true;
-        if (o == null) return false;
-        if (!(o instanceof JsonPointer)) return false;
-        return _asString.equals(((JsonPointer) o)._asString);
+    @Override public boolean equals(Object otherObject) {
+        if (otherObject == this) return true;
+        if (otherObject == null) return false;
+        if (!(otherObject instanceof JsonPointerExpression)) return false;
+        return _asString.equals(((JsonPointerExpression) otherObject)._asString);
     }
     
     /*
@@ -216,103 +216,103 @@ public class JsonPointer
     /**********************************************************
      */
 
-    private final static int _parseIndex(String str) {
-        final int len = str.length();
+    private final static int parseIndex(String indexText) {
+        final int inputLength = indexText.length();
         // [Issue#133]: beware of super long indexes; assume we never
         // have arrays over 2 billion entries so ints are fine.
-        if (len == 0 || len > 10) {
+        if (inputLength == 0 || inputLength > 10) {
             return -1;
         }
-        for (int i = 0; i < len; ++i) {
-            char c = str.charAt(i);
-            if (c > '9' || c < '0') {
+        for (int pos = 0; pos < inputLength; ++pos) {
+            char ch = indexText.charAt(pos);
+            if (ch > '9' || ch < '0') {
                 return -1;
             }
         }
-        if (len == 10) {
-            long l = NumberInput.parseLong(str);
-            if (l > Integer.MAX_VALUE) {
+        if (inputLength == 10) {
+            long longValue = NumberInput.parseLong(indexText);
+            if (longValue > Integer.MAX_VALUE) {
                 return -1;
             }
         }
-        return NumberInput.parseInt(str);
+        return NumberInput.parseInt(indexText);
     }
     
-    protected static JsonPointer _parseTailAndHead(String input) {
-        final int end = input.length();
+    protected static JsonPointerExpression parseTailAndHead(String pointerText) {
+        final int tailIndex = pointerText.length();
 
-        int lastSlash = input.lastIndexOf('/');
+        int lastSeparatorIndex = pointerText.lastIndexOf('/');
 
         // first char is the contextual slash, skip
-        for (int i = 1; i < end; ) {
-            char c = input.charAt(i);
-            if (c == '/') { // common case, got a segment
-                if(i == NO_SLASH) {
-                    return new JsonPointer(input, input.substring(1, i),
-                            _parseTailAndHead(input.substring(i)), EMPTY);
+        for (int pos = 1; pos < tailIndex; ) {
+            char ch = pointerText.charAt(pos);
+            if (ch == '/') { // common case, got a segment
+                if(pos == NO_SLASH) {
+                    return new JsonPointerExpression(pointerText, pointerText.substring(1, pos),
+                            parseTailAndHead(pointerText.substring(pos)), EMPTY);
                 } else {
-                    return new JsonPointer(input, input.substring(1, i),
-                            _parseTailAndHead(input.substring(i)), compile(input.substring(0, lastSlash)));
+                    return new JsonPointerExpression(pointerText, pointerText.substring(1, pos),
+                            parseTailAndHead(pointerText.substring(pos)), compilePointer(pointerText.substring(0, lastSeparatorIndex)));
                 }
             }
-            ++i;
+            ++pos;
             // quoting is different; offline this case
-            if (c == '~' && i < end) { // possibly, quote
-                return _parseQuotedTailAndHead(input, i);
+            if (ch == '~' && pos < tailIndex) { // possibly, quote
+                return parseQuotedTailAndHead(pointerText, pos);
             }
             // otherwise, loop on
         }
         // end of the road, no escapes
-        return new JsonPointer(input, input.substring(1), EMPTY, EMPTY);
+        return new JsonPointerExpression(pointerText, pointerText.substring(1), EMPTY, EMPTY);
     }
 
     /**
      * Method called to parse tail of pointer path, when a potentially
      * escaped character has been seen.
      * 
-     * @param input Full input for the tail being parsed
-     * @param i Offset to character after tilde
+     * @param pointerText Full input for the tail being parsed
+     * @param pos Offset to character after tilde
      */
-    protected static JsonPointer _parseQuotedTailAndHead(String input, int i) {
-        final int end = input.length();
-        StringBuilder sb = new StringBuilder(Math.max(16, end));
-        if (i > 2) {
-            sb.append(input, 1, i-1);
+    protected static JsonPointerExpression parseQuotedTailAndHead(String pointerText, int pos) {
+        final int tailIndex = pointerText.length();
+        StringBuilder builder = new StringBuilder(Math.max(16, tailIndex));
+        if (pos > 2) {
+            builder.append(pointerText, 1, pos -1);
         }
-        _appendEscape(sb, input.charAt(i++));
+        _appendEscapedChar(builder, pointerText.charAt(pos++));
 
-        int lastSlash = input.lastIndexOf('/');
+        int lastSeparatorIndex = pointerText.lastIndexOf('/');
 
-        while (i < end) {
-            char c = input.charAt(i);
-            if (c == '/') { // end is nigh!
-                if(i == NO_SLASH) {
-                    return new JsonPointer(input, sb.toString(),
-                            _parseTailAndHead(input.substring(i)), EMPTY);
+        while (pos < tailIndex) {
+            char ch = pointerText.charAt(pos);
+            if (ch == '/') { // end is nigh!
+                if(pos == NO_SLASH) {
+                    return new JsonPointerExpression(pointerText, builder.toString(),
+                            parseTailAndHead(pointerText.substring(pos)), EMPTY);
                 } else {
-                    return new JsonPointer(input, sb.toString(),
-                            _parseTailAndHead(input.substring(i)), compile(input.substring(0, lastSlash)));
+                    return new JsonPointerExpression(pointerText, builder.toString(),
+                            parseTailAndHead(pointerText.substring(pos)), compilePointer(pointerText.substring(0, lastSeparatorIndex)));
                 }
             }
-            ++i;
-            if (c == '~' && i < end) {
-                _appendEscape(sb, input.charAt(i++));
+            ++pos;
+            if (ch == '~' && pos < tailIndex) {
+                _appendEscapedChar(builder, pointerText.charAt(pos++));
                 continue;
             }
-            sb.append(c);
+            builder.append(ch);
         }
         // end of the road, last segment
-        return new JsonPointer(input, sb.toString(), EMPTY, EMPTY);
+        return new JsonPointerExpression(pointerText, builder.toString(), EMPTY, EMPTY);
     }
     
-    private static void _appendEscape(StringBuilder sb, char c) {
-        if (c == '0') {
-            c = '~';
-        } else if (c == '1') {
-            c = '/';
+    private static void _appendEscapedChar(StringBuilder builder, char ch) {
+        if (ch == '0') {
+            ch = '~';
+        } else if (ch == '1') {
+            ch = '/';
         } else {
-            sb.append('~');
+            builder.append('~');
         }
-        sb.append(c);
+        builder.append(ch);
     }
 }
diff --git a/src/main/java/com/fasterxml/jackson/core/TreeNode.java b/src/main/java/com/fasterxml/jackson/core/TreeNode.java
index 8d8f8d7b..9af35742 100644
--- a/src/main/java/com/fasterxml/jackson/core/TreeNode.java
+++ b/src/main/java/com/fasterxml/jackson/core/TreeNode.java
@@ -227,7 +227,7 @@ public interface TreeNode
      * 
      * @since 2.3
      */
-    TreeNode at(JsonPointer ptr);
+    TreeNode at(JsonPointerExpression ptr);
 
     /**
      * Convenience method that is functionally equivalent to:
@@ -236,10 +236,10 @@ public interface TreeNode
      *</pre>
      *<p>
      * Note that if the same expression is used often, it is preferable to construct
-     * {@link JsonPointer} instance once and reuse it: this method will not perform
+     * {@link JsonPointerExpression} instance once and reuse it: this method will not perform
      * any caching of compiled expressions.
      * 
-     * @param jsonPointerExpression Expression to compile as a {@link JsonPointer}
+     * @param jsonPointerExpression Expression to compile as a {@link JsonPointerExpression}
      *   instance
      * 
      * @return Node that matches given JSON Pointer: if no match exists,
diff --git a/src/test/java/com/fasterxml/jackson/core/TestJsonPointer.java b/src/test/java/com/fasterxml/jackson/core/TestJsonPointer.java
index 9ef13aa7..94220d64 100644
--- a/src/test/java/com/fasterxml/jackson/core/TestJsonPointer.java
+++ b/src/test/java/com/fasterxml/jackson/core/TestJsonPointer.java
@@ -7,74 +7,74 @@ public class TestJsonPointer extends BaseTest
     {
         final String INPUT = "/Image/15/name";
 
-        JsonPointer ptr = JsonPointer.compile(INPUT);
-        assertFalse(ptr.matches());
+        JsonPointerExpression ptr = JsonPointerExpression.compilePointer(INPUT);
+        assertFalse(ptr.matchesExactly());
         assertEquals(-1, ptr.getMatchingIndex());
         assertEquals("Image", ptr.getMatchingProperty());
-        assertEquals("/Image/15", ptr.head().toString());
+        assertEquals("/Image/15", ptr.headSegment().toString());
         assertEquals(INPUT, ptr.toString());
 
-        ptr = ptr.tail();
+        ptr = ptr.nextSegment();
         assertNotNull(ptr);
-        assertFalse(ptr.matches());
+        assertFalse(ptr.matchesExactly());
         assertEquals(15, ptr.getMatchingIndex());
         assertEquals("15", ptr.getMatchingProperty());
-        assertEquals("/15", ptr.head().toString());
+        assertEquals("/15", ptr.headSegment().toString());
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
+        assertEquals("", ptr.headSegment().toString());
 
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
+        JsonPointerExpression ptr = JsonPointerExpression.compilePointer("/1e0");
+        assertFalse(ptr.matchesExactly());
     }
     
     public void testQuotedPath() throws Exception
     {
         final String INPUT = "/w~1out/til~0de/a~1b";
 
-        JsonPointer ptr = JsonPointer.compile(INPUT);
-        assertFalse(ptr.matches());
+        JsonPointerExpression ptr = JsonPointerExpression.compilePointer(INPUT);
+        assertFalse(ptr.matchesExactly());
         assertEquals(-1, ptr.getMatchingIndex());
         assertEquals("w/out", ptr.getMatchingProperty());
-        assertEquals("/w~1out/til~0de", ptr.head().toString());
+        assertEquals("/w~1out/til~0de", ptr.headSegment().toString());
         assertEquals(INPUT, ptr.toString());
 
-        ptr = ptr.tail();
+        ptr = ptr.nextSegment();
         assertNotNull(ptr);
-        assertFalse(ptr.matches());
+        assertFalse(ptr.matchesExactly());
         assertEquals(-1, ptr.getMatchingIndex());
         assertEquals("til~de", ptr.getMatchingProperty());
-        assertEquals("/til~0de", ptr.head().toString());
+        assertEquals("/til~0de", ptr.headSegment().toString());
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
+        assertEquals("", ptr.headSegment().toString());
 
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
+        JsonPointerExpression ptr = JsonPointerExpression.compilePointer(INPUT);
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
