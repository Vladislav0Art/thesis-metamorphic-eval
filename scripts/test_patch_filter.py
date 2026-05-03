"""
Manual smoke tests for transform.patch_filter.

Run from repo root:
    python scripts/test_patch_filter.py
"""

import sys
sys.path.insert(0, 'scripts')

from transform.patch_filter import filter_import_changes


def check(label, cond, detail=''):
    status = 'PASS' if cond else 'FAIL'
    print(f"  [{status}] {label}" + (f": {detail}" if detail else ''))
    return cond


def test_pure_import_reorder():
    print("\n=== Test 1: Pure import reorder (2 file sections) ===")
    patch = """\
diff --git a/core/src/test/java/com/alibaba/fastjson2/eishay/ParserTest.java b/core/src/test/java/com/alibaba/fastjson2/eishay/ParserTest.java
index 5aef2bef9..f65eaebf9 100644
--- a/core/src/test/java/com/alibaba/fastjson2/eishay/ParserTest.java
+++ b/core/src/test/java/com/alibaba/fastjson2/eishay/ParserTest.java
@@ -1,9 +1,9 @@
 package com.alibaba.fastjson2.eishay;

-import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.eishay.vo.Image;
 import com.alibaba.fastjson2.eishay.vo.Media;
 import com.alibaba.fastjson2.eishay.vo.MediaContent;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.JSONB;
 import com.alibaba.fastjson2.JSONReader;
 import com.alibaba.fastjson2.JSONWriter;
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1146.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1146.java
index de885dd46..d721afad8 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1146.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/issue_1100/Issue1146.java
@@ -1,7 +1,7 @@
 package com.alibaba.fastjson2.v1issues.issue_1100;

-import com.alibaba.fastjson2.annotation.JSONType;
 import com.alibaba.fastjson2.JsonMapper;
+import com.alibaba.fastjson2.annotation.JSONType;
 import org.junit.jupiter.api.Test;

 import static org.junit.jupiter.api.Assertions.assertEquals;"""

    r = filter_import_changes(patch)
    check("filtered patch is empty", r.filtered_patch.strip() == '', repr(r.filtered_patch.strip()[:80]))
    check("2 fixes recorded", len(r.fixes) == 2, f"got {len(r.fixes)}")
    check("both are import_reorder", all(f.problem_type == 'import_reorder' for f in r.fixes))
    check("fix 1 has removed_block", bool(r.fixes[0].removed_block))
    check("fix 1 file path", r.fixes[0].file == 'core/src/test/java/com/alibaba/fastjson2/eishay/ParserTest.java')


def test_wildcard_removal_mixed_hunk():
    print("\n=== Test 2: Wildcard removal in hunk that also has an intentional rename ===")
    patch = """\
diff --git a/core/src/test/java/com/alibaba/fastjson2/v1issues/Issue1344.java b/core/src/test/java/com/alibaba/fastjson2/v1issues/Issue1344.java
index 95cac6f2d..f77fcfd99 100644
--- a/core/src/test/java/com/alibaba/fastjson2/v1issues/Issue1344.java
+++ b/core/src/test/java/com/alibaba/fastjson2/v1issues/Issue1344.java
@@ -1,11 +1,9 @@
 package com.alibaba.fastjson2.v1issues;

-import com.alibaba.fastjson2.JSON;
+import com.alibaba.fastjson2.JsonMapper;
 import com.alibaba.fastjson2.annotation.JSONCreator;
 import org.junit.jupiter.api.Test;

-import static junit.framework.TestCase.*;
-
 /**
  * Created by wenshao on 26/07/2017.
  */
@@ -13,8 +11,8 @@
     @Test
     public void test_for_issue() throws Exception {
         TestException testException = new TestException("aaa");
-        String json = JSON.toJSONString(testException);
-        TestException o = JSON.parseObject(json, TestException.class);
+        String json = JsonMapper.toJsonString(testException);
+        TestException o = JsonMapper.parseJsonObject(json, TestException.class);
         assertNull(o.getMessage());
     }"""

    r = filter_import_changes(patch)
    check("exactly 1 fix", len(r.fixes) == 1, f"got {len(r.fixes)}")
    check("fix is wildcard_import_removal", r.fixes[0].problem_type == 'wildcard_import_removal')
    check("removed_lines contains wildcard",
          any('import static junit.framework.TestCase.*' in l for l in r.fixes[0].removed_lines),
          str(r.fixes[0].removed_lines))
    check("JSON->JsonMapper rename preserved (first hunk still present)",
          '-import com.alibaba.fastjson2.JSON;' in r.filtered_patch)
    check("+import JsonMapper preserved",
          '+import com.alibaba.fastjson2.JsonMapper;' in r.filtered_patch)
    check("wildcard line removed from patch (no longer a -line)",
          '-import static junit.framework.TestCase.*;' not in r.filtered_patch)
    check("wildcard line kept as context (still present as a space-line)",
          ' import static junit.framework.TestCase.*;' in r.filtered_patch)
    check("first hunk old_count unchanged (11 lines in old file)",
          '@@ -1,11 +1,11 @@' in r.filtered_patch)
    check("second hunk (method rename) preserved",
          'JsonMapper.toJsonString' in r.filtered_patch)

    print("\n  --- Filtered patch ---")
    for line in r.filtered_patch.splitlines():
        print(f"  {line}")


def test_no_import_noise():
    print("\n=== Test 3: Patch with no import noise — passes through unchanged ===")
    patch = """\
diff --git a/Foo.java b/Foo.java
index abc..def 100644
--- a/Foo.java
+++ b/Foo.java
@@ -5,7 +5,7 @@
 public class Foo {
     public void bar() {
-        String x = doOld();
+        String x = doNew();
     }
 }"""

    r = filter_import_changes(patch)
    check("no fixes", len(r.fixes) == 0, f"got {len(r.fixes)}")
    check("patch unchanged", r.filtered_patch == patch, repr(r.filtered_patch[:80]))


def test_empty_patch():
    print("\n=== Test 4: Empty patch — returns as-is ===")
    r = filter_import_changes('')
    check("empty in, empty out", r.filtered_patch == '')
    check("no fixes", len(r.fixes) == 0)


def test_hunk_header_offset_after_wildcard_removal():
    """Wildcard-only hunk is dropped; its net change (-1) still shifts the next hunk's +start."""
    print("\n=== Test 5: Hunk header new_start corrected after wildcard removal ===")
    # First hunk: only the wildcard removal (no other changes).
    # After converting to context, has_changes()=False → hunk dropped.
    # Net change was -1 → offset +1 applied to subsequent hunks.
    # Second hunk originally at +9 → adjusted to +10.
    patch = """\
diff --git a/Foo.java b/Foo.java
index abc..def 100644
--- a/Foo.java
+++ b/Foo.java
@@ -1,5 +1,4 @@
 package com.example;

-import static com.example.Util.*;
 import com.example.A;
 import com.example.B;
@@ -10,6 +9,6 @@
     public void test() {
-        Old.call();
+        New.call();
     }
 }"""

    r = filter_import_changes(patch)
    check("1 fix", len(r.fixes) == 1)
    check("fix is wildcard_import_removal", r.fixes[0].problem_type == 'wildcard_import_removal')
    check("wildcard-only first hunk is dropped", '@@ -1,' not in r.filtered_patch)
    check("second hunk new_start adjusted to +10", '@@ -10,6 +10,6 @@' in r.filtered_patch,
          repr([l for l in r.filtered_patch.splitlines() if l.startswith('@@')]))
    print("\n  --- Filtered patch ---")
    for line in r.filtered_patch.splitlines():
        print(f"  {line}")


if __name__ == '__main__':
    test_pure_import_reorder()
    test_wildcard_removal_mixed_hunk()
    test_no_import_noise()
    test_empty_patch()
    test_hunk_header_offset_after_wildcard_removal()
    print("\nDone.")
