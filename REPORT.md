# Agent Trajectory Analysis Report

---------- GPT-5.4 ----------

**Setup:** 20 Java Multi-SWE-bench instances × 5 independent runs × 5 transformation strategies.
**Pass rate totals:** s0-original=7, s1-renaming=3, s2-structural=4, s3-problem-statement=7, s4-combined=3 (unique instances resolved at least once; a single instance solved across all 5 runs still counts as 1 here — use the R-column lists below for the full picture).

---


The most interesting findings:

`elastic__logstash-14970/14981` — drop from 4/5 → 0/5 under s1 because the agent hallucinates a wrong renamed class name (e.g., DeadLetterQueueFileWriter) and gets 4–6 consecutive zero-result searches before giving up.

`elastic__logstash-16681` — goes from 1/5 (s0) → 5/5 (s4). The combined rename breaks the agent's class-name search, forcing it to fall back to semantic method searches (unregisterSender, notifyAll). This produces a 9-edit comprehensive fix instead of s0's 2-edit minimal one — the transformation accidentally creates a better strategy.

`mockito__mockito-3129` — the inverse: in s0 the agent cycles through imports/edits in 4 of 5 runs (memorized-but-wrong pattern). Transformations disrupt the shortcut and force real problem-solving → improves to 4/5 under s1 and s3.

`elastic__logstash-16579` — only solvable under s3 (problem-statement only). A Java+Ruby hybrid that requires 19 searches (most of any trajectory). The original problem statement is apparently too vague to guide the agent to the right code path.

`fasterxml__jackson-databind-1923` — drops to 0/5 under s2 because the agent's path-based Spring stub discovery (-path '*org/springframework*') breaks when the test directory is restructured.


---

## === s0-original ===

**Resolved instances:** elastic__logstash-14970 (R2,R3,R4,R5), elastic__logstash-14981 (R1,R3,R4,R5), fasterxml__jackson-databind-1923 (R2,R3,R5), google__gson-1093 (R2,R3), elastic__logstash-16681 (R2), fasterxml__jackson-core-183 (R3), mockito__mockito-3129 (R4)

---

### elastic__logstash-14970

**[run-2]** _(46 steps, exit_status: submitted)_
1. The agent opens with a direct, confident class-name search: `search_dir "class DeadLetterQueueWriter" .` in step 2. It immediately gets 3 matches and opens `DeadLetterQueueWriter.java` in step 3 — no wasted exploration.
2. Root cause is quickly traced: `readTimestampOfLastEventInSegment()` computes `lastBlockId = ceil((fileSize - VERSION_SIZE) / BLOCK_SIZE) - 1`, which becomes -1 for a 1-byte file (header-only segment), causing `seekToBlock(-1)` to throw. The agent follows up with searches for `"VERSION_SIZE"` and `"VERSION ="` constants in `RecordIOReader.java` to confirm the arithmetic.
3. The fix is minimal: 5 edits total — a guard `if (lastBlockId < 0) return Optional.empty()` added before the loop in `readTimestampOfLastEventInSegment()`, plus a regression test `testOpenWithHeaderOnlySegment` added to `DeadLetterQueueWriterTest.java`.
4. The agent runs `./gradlew :logstash-core:test --tests ...DeadLetterQueueWriterTest` three times — once to confirm the test fails without the fix, then to verify the fix, then a targeted test run. This verify-fix-verify pattern shows confident, structured debugging.
5. The agent opens `RecordIOReader.java` to understand the constants but makes no edits there — it correctly identifies that only the writer's method needs the guard. Total unique files touched in edits: 2.

---

### elastic__logstash-14981

**[run-1]** _(39 steps, exit_status: submitted)_
1. Same DLQ writer class as 14970 but a slightly different manifestation. The agent's first search is identical — `search_dir "class DeadLetterQueueWriter" .` — demonstrating the same pattern anchor.
2. The agent additionally opens `RecordIOWriter.java` (not touched by 14970's run) to inspect `VERSION_SIZE` definition. This adds a few steps but shows the agent is more careful about understanding where the constant originates.
3. 6 edits are made: the guard fix in `readTimestampOfLastEventInSegment()` is similar to 14970, but the test structure is slightly different — the agent writes `testWriterInitializesWithHeaderOnlySegment` which focuses on the initialization path rather than the open path.
4. Fewer total steps (39) than 14970's run-2 (46) despite more careful constant-lookup. This suggests the run-1 seed produced a more direct exploration sequence — the agent didn't open the test file as many times (18 unique opens vs 25 for 14970).
5. Also greps `build/test-results` for `<failure` after a test run — a forensic step to understand a test failure message before making the final edit. This debugging tactic is not seen in 14970's trajectory.

---

### fasterxml__jackson-databind-1923

**[run-2]** _(36 steps, exit_status: submitted)_
1. Agent uses `find_file "SubTypeValidator.java" src` as its first anchor — class name derived from the issue title mentioning "SubTypeValidator" and "Spring Security". Immediately opens the file.
2. A sophisticated test-infrastructure discovery step: `find src/test/java -path '*org/springframework*' -o -path '*springframework*'` reveals that there are no pre-existing Spring Security stub classes in the test tree. The agent then creates them from scratch.
3. The agent creates two stub classes: `org.springframework.security.core.GrantedAuthority` (interface) and `org.springframework.security.core.AuthorityList` (class implementing it). These are minimal stubs — not pulled from training data as correct Spring Security implementations but purpose-built for the test.
4. Fixes `SubTypeValidator.java` by adding `org.springframework.security` to the blocked-type prefixes.
5. Only 2 mvn test runs, both targeting `IllegalTypesCheckTest`. The agent's approach is surgical: create stubs, patch validator, verify. No redundant exploration.
6. The 8 edits span both creation of new stub files and modification of SubTypeValidator — a multi-file fix pattern rare in other trajectories.

---

### google__gson-1093

**[run-2]** _(43 steps, exit_status: submitted)_
1. Minimal search footprint: only 2 `find_file` queries — `"JsonWriter.java"` then `"JsonWriterTest.java"`. The agent goes directly to the implementation without any class-hierarchy or package exploration.
2. The fix targets `JsonWriter.value(double)` at lines 486–522 — the method handling double serialization. The agent opens the file multiple times (15 total opens) to navigate different parts of a large file rather than scrolling.
3. The test added is `testLenientNonFiniteDoubles` — mirrors the exact terminology of the issue (lenient mode, non-finite doubles). The agent connects issue language to code semantics without extra search steps.
4. 8 edits, 2 mvn test runs. The second test run confirms the fix. Compact and efficient trajectory.
5. Compared to other instances, this trajectory shows the agent operating near its theoretical minimum: it knows exactly which class handles JSON writing and goes straight there. This instance is likely close to training data (Gson is a well-known library), enabling direct pattern-matching to the fix location.

---

### elastic__logstash-16681

**[run-2]** _(45 steps, exit_status: submitted via exit_cost)_
1. The agent correctly identifies `PipelineBusV2.java` as the target via `search_dir "class PipelineBusV2" .`. However, the trajectory shows a striking pattern: PipelineBusV2.java is opened **19 times** — the most re-reads of any single file in any trajectory. This indicates the agent repeatedly needs to revisit the concurrent code to understand state transitions.
2. The agent spends 5 search steps trying to find a `PipelineBusV2Test.java` — which does not exist (the tests are in `PipelineBusTest.java`). This dead-end wastes multiple steps.
3. Only **2 edits** are made despite 45 steps — the agent struggles to converge on the fix for a complex deadlock. One edit modifies the `AddressStateMapping` inner class, and one follows up. No tests are run at all before exit_cost.
4. The `exit_cost` exit status (cost limit reached, auto-submitted) suggests the agent exhausted its budget before it could validate or refine its fix. In the 4 other runs where this instance is not resolved, a similar pattern likely plays out with a different (wrong) fix patch submitted.
5. The low edit count combined with many file opens and 0 test runs is characteristic of a difficult concurrency bug — the agent understands the code structurally but cannot easily determine the right synchronization fix without running tests.

---

### fasterxml__jackson-core-183

**[run-3]** _(56 steps, exit_status: submitted)_
1. Minimal searching (only 2 queries): `find src -type f | grep 'TextBuffer|BufferRecycler|Test'` and `search_dir "getTextCharacters()" src/test`. The agent identifies the issue as related to `getTextBuffer()` consistency for empty buffers.
2. Opens **29 files** total — the highest file-open count across all resolved trajectories. TextBuffer.java alone is opened many times; the agent re-reads it repeatedly to navigate a large class (~600 lines) without a scroll command.
3. 10 edits to fix `getTextBuffer()` — when `_inputBuffer` is shared (the empty case), the method must return a stable representation. The agent works through multiple attempts, visible as 10 separate edit commands.
4. The regression test is named `testEmptyGetText...` and placed in `TestTextBuffer.java`. 3 mvn test runs confirm the fix converges. The multiple edits (including some that appear to roll back and retry) suggest the agent was iteratively debugging the fix.
5. This is the most complex single-class fix in the benchmark — TextBuffer has many internal state variables. The long trajectory is justified by the complexity.

---

### mockito__mockito-3129

**[run-4]** _(62 steps, exit_status: submitted via exit_cost)_
1. The highest search count in s0 (9 searches): the agent probes `"getMockMaker("`, `"getInlineMockMaker"`, interface/class declarations, and plugin-loading patterns. Mockito's plugin infrastructure spans many files, requiring extensive orientation.
2. Files touched: `MockitoPlugins.java` (interface), `DefaultMockitoFramework.java`, `Plugins.java`, `DefaultMockitoPlugins.java`, `MockitoPluginsTest.java`, `MockUtil.java`, `MockMakers.java` — 7 distinct source files, the widest blast radius of any instance.
3. 10 edits. The agent modifies the `MockitoPlugins` interface to add a `getMockMaker()` default method, then updates the framework and plugin implementations to wire it up.
4. 2 gradlew test runs. The exit_cost cutoff triggers before the agent finishes refinement, but the submitted patch is correct for run-4.
5. Runs 1–3 fail to produce a working patch. The successful run-4 submission suggests that the correct fix requires a specific sequence of interface + implementation edits that only the run-4 sampling seed happens to land on cleanly before the budget runs out.

---

## === s1-renaming ===

**Transformation:** Class names, method names, and variable names are renamed project-wide (compilation-preserving). The problem statement text may also reference the new names.

**Resolved instances:** mockito__mockito-3129 (R1,R2,R3,R4), fasterxml__jackson-databind-1923 (R5), elastic__logstash-16681 (R1,R3,R4)

**Instances that DROPPED to zero:** elastic__logstash-14970, elastic__logstash-14981 (both 4/5 in s0 → 0/5 in s1), google__gson-1093 (2/5 → 0/5), fasterxml__jackson-core-183 (1/5 → 0/5)

---

### mockito__mockito-3129

**[run-1]** _(70 steps, exit_status: submitted via exit_cost)_
1. **Renamed files present:** `MockUtil` → `MockUtils`, `MockitoPlugins` → `MockitoPluginRegistry`, `DefaultMockitoPlugins` → `MockitoDefaultPlugins`. The agent correctly adapts its initial search: `find . -name "MockUtils.java" -o -name "MockitoPluginRegistry.java"` — it uses the new names, not the old ones.
2. The renamed interface `MockitoPluginRegistry` has a name that more clearly signals its role in the plugin system. The agent navigates to it efficiently via the `find` command rather than a content search.
3. Crucially, the agent also uses method-name searches that are invariant to renaming: `grep -R "getMockMaker"` and `grep -R "getInlineMockMaker"`. These method names appear to be preserved in the renamed codebase, giving the agent stable anchors.
4. Fewer edits than s0 (7 vs 10), and only 1 test run. The clearer naming hierarchy (`MockitoPluginRegistry` for the interface, `MockitoDefaultPlugins` for the implementation) appears to reduce the cycling behavior observed in s0's runs 1–3.
5. This instance improves dramatically from 1/5 (s0) to 4/5 (s1). The renaming resolves ambiguity between `MockUtil` and `MockitoPlugins` which in s0 caused cyclic imports/edits. When the plugin-registry class has "Registry" in its name, the agent's interface vs. implementation distinction becomes cleaner.

---

### fasterxml__jackson-databind-1923

**[run-5]** _(28 steps, exit_status: submitted — SHORTEST resolved trajectory for this instance)_
1. **Renamed class:** `SubTypeValidator` → `SubtypeValidator` (lowercase 't'). The agent's first search correctly targets the new name: `find src -type f | grep -E 'SubtypeValidator|DefaultTyping|subtype|Polymorphic|Security'` — finds it immediately.
2. Unlike s0's run-2 (which had to create Spring Security stubs from scratch), this run discovers a pre-existing `org/springframework/jacksontest/BogusApplicationContext.java` file in the test tree. The agent uses this existing infrastructure rather than creating stubs, resulting in only 4 edits (vs s0's 8).
3. The trajectory is 28 steps — 8 fewer than s0's run-2. The renaming appears to have made the class hierarchy slightly cleaner to navigate.
4. Despite only being solved in 1 of 5 runs (vs s0's 3/5), this run-5 is the most efficient solve. The majority of s1 runs for this instance likely fail at the class-name inference stage or suffer from the renamed blocklist entries in SubtypeValidator making the fix location harder to identify.

---

### elastic__logstash-16681

**[run-1]** _(40 steps, exit_status: submitted via exit_cost)_
1. **Critical search confusion from renaming:** The agent's first 4 searches are `find . -name "PipelineEventBusV2.java"`, `grep -R "class PipelineEventBusV2"`, `find_file "PipelineEventBusV2.java"`, and `search_dir "PipelineEventBusV2"`. In the s1-renamed codebase, the actual class is still named `PipelineBusV2` but the problem statement apparently references a renamed form `PipelineEventBusV2`. All 4 searches return no results — 4 wasted steps.
2. The agent recovers by searching for pipeline-related files by directory: `find . (\path "*/src/main/java/*" -o -path "*/src/test/java/*") | grep "pipeline"`. This correctly reveals `PipelineBusV2.java` and the agent pivots to it.
3. The agent also opens `PipelineBus.java` (the interface) — not seen in s0's trajectory. The renaming of the problem statement causes the agent to be less certain about which class implements the bus, so it reads both the interface and the implementation.
4. Only 1 edit (vs s0's 2), and 2 test runs. Despite the initial search confusion costing 4 steps, the agent still produces a working fix. This explains the improvement from 1/5 → 3/5: the renaming causes confusion but not catastrophic failure; in 3 of 5 runs the agent recovers in time.

**Cross-strategy insight (why elastic__logstash-14970/14981 drop to 0/5 under s1):** These two DLQ instances rely on the agent's ability to search for `"class DeadLetterQueueWriter"` as the entry point. Under s1, the class is renamed (e.g., to something with "File" suffix or different casing). Exploration of a failed s1 run for elastic__logstash-14970 showed the agent searching for `"DeadLetterQueueFileWriter"` — a non-existent name hallucinated from the renamed problem statement. With 4–6 consecutive zero-result searches, the agent never reaches the right file. The DLQ instances are particularly vulnerable because (unlike logstash-16681) there is no interface/directory fallback path — the fix is entirely within one class that can only be found by name.

---

## === s2-structural ===

**Transformation:** Methods in the changed files are sorted Z→A within each class; some files may be relocated to different package directories. No identifier renaming.

**Resolved instances:** elastic__logstash-14970 (R1,R2,R3,R4,R5), elastic__logstash-14981 (R1,R2,R3,R4,R5), elastic__logstash-16681 (R2,R4,R5), mockito__mockito-3129 (R1,R3)

**Notable improvements over s0:** elastic__logstash-14970 (4/5 → 5/5), elastic__logstash-14981 (4/5 → 5/5), elastic__logstash-16681 (1/5 → 3/5)

**Instances that DROPPED to zero:** fasterxml__jackson-databind-1923 (3/5 → 0/5), google__gson-1093 (2/5 → 0/5), fasterxml__jackson-core-183 (1/5 → 0/5)

---

### elastic__logstash-14970

**[run-1]** _(46 steps, exit_status: submitted)_
1. Essentially the same trajectory as s0. First action: `search_dir "class DeadLetterQueueWriter" .` — succeeds because structural transformation doesn't change class names. The agent reaches the implementation in the same number of steps.
2. A notable difference: the agent's second search is `search_dir "EMPTY_DLQ" logstash-core/src/test/java` (vs s0's `"VERSION_SIZE"`). In the s2-sorted codebase, the constant `EMPTY_DLQ` (or a similar test-related constant) is more prominent due to method ordering — the agent latches onto a different landmark in the test file.
3. 6 edits (vs s0's 5), 3 test runs. The fix is identical in nature: guard `lastBlockId < 0` and add a regression test `testInitializeWithHeaderOnlySegment`.
4. This instance is now solved in ALL 5 runs (vs 4/5 in s0). The structural transformation may have slightly improved the determinism of the fix path: with methods sorted alphabetically, `readTimestampOfLastEventInSegment` appears in a more predictable position in the sorted file, and the agent's file-navigation (line-number based `open`) doesn't need to search for the right line range.

---

### elastic__logstash-14981

**[run-1]** _(29 steps, exit_status: submitted — FASTEST trajectory for this instance across all strategies)_
1. Only 2 searches: `find_file "DeadLetterQueueWriter.java" .` and `search_dir "DeadLetterQueueWriter" logstash-core/src/test`. Minimal overhead — the agent goes straight to the implementation and test.
2. Only 2 edits total — the most surgical fix seen for this instance: one edit to the guard in `readTimestampOfLastEventInSegment()` and one test addition. No exploratory detours into RecordIOWriter or RecordIOReader.
3. The method sorting in s2 may have paradoxically made the fix location easier to predict. If `readTimestampOfLastEventInSegment` falls at a predictable sorted position, the agent needs fewer re-reads to stay oriented, reducing step count from 39 (s0 run-1) to 29 (s2 run-1).
4. Improves from 4/5 (s0) to 5/5 (s2). The structural transformation appears to stabilize this instance without disrupting it.

---

### elastic__logstash-16681

**[run-2]** _(46 steps, exit_status: submitted via exit_cost)_
1. More direct search strategy than s0: `find_file "PipelineBusV2.java"` (vs s0's `search_dir "class PipelineBusV2"`). The agent goes straight for the filename rather than class declaration.
2. PipelineBusV2.java is opened 21 times (vs s0's 19) — even more re-reads, consistent with the difficulty of the concurrency bug.
3. 3 edits (vs s0's 2), 0 test runs. Still exits via cost limit. The structural changes (method sorting) don't change the synchronization fix required, but the agent spends slightly more time re-navigating the sorted file.
4. Improves from 1/5 → 3/5 overall. This improvement likely comes from the sorted method ordering making the `unregisterSender` / `blockOnUnlisten` methods easier to locate consistently across seeds.

---

### mockito__mockito-3129

**[run-1]** _(71 steps, exit_status: submitted via exit_cost)_
1. **File has moved:** `MockitoPlugins.java` is located in `plugins/api/` subdirectory rather than `plugins/` in the original. The agent must use content-based search to find it: `search_dir "interface MockitoPlugins"` — it cannot rely on knowing the exact path.
2. The agent makes **21 edits** — the highest edit count across all resolved trajectories. Despite the correct overall approach (wiring `getMockMaker()` through the interface), the agent cycles through import statements and method signatures multiple times.
3. Despite the high edit count, the fix is correct in R1 and R3. The file relocation forces the agent to reason about the plugin system from interface discovery rather than path knowledge, which appears to produce a more thorough (if longer) exploration.
4. 4 test runs validate intermediate and final states. The additional test runs (vs s0's 2) reflect the extra uncertainty introduced by the moved file.

**Cross-strategy insight (why jackson-databind-1923 drops to 0/5 under s2):** The s2 structural transformation reorganizes the test package hierarchy. In s0, the agent uses `find src/test/java -path '*org/springframework*'` to discover (or not discover) existing Spring Security test stubs — a path-based search that depends on directory structure. Under s2, the Spring Security stubs or the test directory structure are reorganized, causing this search to fail. Without the infrastructure discovery step, the agent tries to create Spring stubs without understanding the existing test imports, producing an incomplete fix. This path-dependency is fragile under structural reorganization.

---

## === s3-problem-statement ===

**Transformation:** Only the problem statement text is rewritten — code is identical to s0. The issue description is reformulated, potentially with different terminology, additional context, or different emphasis.

**Resolved instances:** elastic__logstash-14970 (R1,R2,R3,R4,R5), elastic__logstash-14981 (R1,R2,R3,R4,R5), google__gson-1093 (R1,R3), elastic__logstash-16681 (R1), fasterxml__jackson-core-183 (R2), mockito__mockito-3129 (R2,R3,R4,R5), elastic__logstash-16579 (R2)

**Notable improvements:** elastic__logstash-14970 (4/5 → 5/5), elastic__logstash-14981 (4/5 → 5/5), mockito__mockito-3129 (1/5 → 4/5), elastic__logstash-16681 properly submitted (R1), elastic__logstash-16579 unlocked from 0/5 → 1/5.

---

### elastic__logstash-14970

**[run-1]** _(39 steps, exit_status: submitted — 15% fewer steps than s0's 46)_
1. Same entry search `"class DeadLetterQueueWriter"` (code is unchanged), but the agent's second and only other search is `search_dir "javaTests" .` — it's checking Gradle task naming to run tests correctly. This extra care suggests the problem statement rewrite provided explicit guidance about the test harness to use.
2. 7 edits (vs s0's 5) — the agent writes a slightly more comprehensive test, naming it `testInitializeWithVersionOnlySegment`, mirroring the rewritten problem statement's language ("version-only segment" instead of "header-only segment").
3. The terminology from the rewritten problem statement directly shapes the test name the agent writes — showing how problem framing propagates into agent decisions at the code level.
4. Achieves 5/5 consistency (up from 4/5). The rewrite appears to resolve the ambiguity that caused one s0 run to fail.

---

### elastic__logstash-14981

**[run-1]** _(47 steps, exit_status: submitted)_
1. **Different exploration order vs s0:** The agent opens `DeadLetterQueueWriterTest.java` FIRST (before the implementation). This test-first approach is unusual and suggests the problem statement rewrite framed the issue in terms of expected test behavior rather than implementation bugs.
2. The agent introduces a constant `EMPTY_DLQ = VERSION_SIZE` directly in the test class — adopting problem-statement terminology. This constant is not in the original test code but the rewritten problem statement apparently uses this term.
3. 8 edits and 4 test runs (most test runs for this instance across any strategy). The extra test runs suggest the agent is more uncertain about the fix — the test-first approach forces it to validate more iterations.
4. More steps (47) than s2's fastest run (29) but similar to s0 (39). The problem-statement rewrite makes the agent more test-focused but doesn't reduce complexity.

---

### google__gson-1093

**[run-1]** _(43 steps, exit_status: submitted)_
1. Same minimal search footprint as s0: `find_file "JsonWriter.java"` and `find_file "JsonWriterTest.java"`. The code is unchanged, so navigation is identical.
2. 9 edits (vs s0's 8) and 3 test runs (vs s0's 2). Slightly more testing effort, consistent with a more test-focused problem description.
3. Overall behavior is very similar to s0 — the problem-statement rewrite doesn't significantly change how the agent tackles this well-understood class.

---

### elastic__logstash-16681

**[run-1]** _(40 steps, exit_status: submitted — the ONLY clean submission for this instance across all strategies)_
1. This is the most significant finding for this instance: s3's run-1 is the only trajectory across all 5 strategies that exits via `submitted` (not `exit_cost`). The agent runs **3 tests** (vs 0 for s0/s2) and validates its fix before submitting.
2. Fewer files opened (12 vs s0's 19) — the problem-statement rewrite evidently directs the agent more precisely. One of the 3 searches targets `"class Testable extends PipelineBusV2"` — the agent knows to look for the test subclass that exercises the deadlock scenario, which it could only know from the rewritten problem statement context.
3. 3 edits (vs s0's 2) include adding a regression test `v2DoesNotDeadlockWhenAddressMutationNotifiesWhileBlockingUnlistenHoldsListenerLock` — a test with a highly specific name encoding the exact deadlock condition. The agent derived this test name from the problem statement framing.
4. This instance is solved only in R1 (1/5 runs, same rate as s0). Despite the trajectory quality being the best across all strategies, the fix still requires exact concurrency reasoning and doesn't generalise to other seeds.

---

### fasterxml__jackson-core-183

**[run-2]** _(57 steps, exit_status: submitted)_
1. More search effort than s0 (5 searches vs 2): the agent tries multiple variants of `find_file "TextBufferTest.java"` before finding the test file named `TestTextBuffer.java`. The rewritten problem statement may use different terminology that slightly misdirects the test-file search.
2. Files opened (22) and edits (9) are similar to s0 (29 opens, 10 edits). The fix is the same `getTextBuffer()` consistency repair.
3. 3 test runs. The trajectory length (57 steps vs 56) is virtually identical to s0.

---

### mockito__mockito-3129

**[run-2]** _(72 steps, exit_status: submitted via exit_cost)_
1. The agent opens **45 files** — the highest file-open count of any trajectory in this entire analysis. This indicates extensive framework exploration driven by a more detailed problem description that references many interfaces and classes.
2. 8 edits and **0 test runs**. Despite no test validation, the submitted patch is correct in runs 2–5. The problem-statement rewrite appears to provide enough implementation context that the agent can reason about correctness statically.
3. Searches include `"getMockMaker"`, `grep -R "implements MockitoPlugins"`, `"getPlugins()"` — method-centric queries that search for the correct integration points regardless of file layout.
4. Improves dramatically from 1/5 (s0) to 4/5 (s3). The rewritten problem statement apparently clarifies the API contract that `getMockMaker()` must satisfy, allowing the agent to make the correct interface + implementation changes consistently.

---

### elastic__logstash-16579

**[run-2]** _(57 steps, exit_status: submitted via exit_cost — the ONLY resolved run for this instance across all strategies)_
1. This is a hybrid Java + Ruby codebase: `BufferedTokenizerExt.java` (Java implementation) with `buftok_spec.rb` (Ruby test specs). The agent makes 7 edits spanning both files — the only instance requiring cross-language edits.
2. The agent performs **19 searches** — by far the most of any trajectory in this analysis. It searches for `"BufferedTokenizer"`, `"input buffer full"`, `"FileWatch::BufferedTokenizer.new"`, `"BufferedTokenizer.new("`, and more. This extreme search density reflects genuine difficulty finding the relevant code in an unfamiliar Ruby/Java hybrid structure.
3. The rewritten problem statement (s3) appears to be the only version that gives the agent enough context to attempt this fix at all. In s0, s1, s2, and s4, this instance produces zero resolved runs — the original problem statement may be too vague about the buffer overflow behavior to guide the agent to the right code path.
4. 2 test runs via `./gradlew :logstash-core:rubyTests` (running Ruby specs from the Java test harness) and `compileJava`. The mixed-language test setup adds complexity.
5. The instance is solved via exit_cost auto-submission, meaning the agent hit its budget limit — but the submitted patch happened to be correct. This is the most serendipitous resolution in the dataset.

---

## === s4-combined ===

**Transformation:** All transformations applied simultaneously — identifier renaming (s1) + structural reorganisation (s2) + problem-statement rewrite (s3).

**Resolved instances:** elastic__logstash-16681 (R1,R2,R3,R4,R5), fasterxml__jackson-core-183 (R3), mockito__mockito-3129 (R3,R4,R5)

**Dramatic improvement:** elastic__logstash-16681 (1/5 in s0 → 5/5 in s4 — 100% consistency)

**Instances that dropped from s0 to zero:** elastic__logstash-14970, elastic__logstash-14981 (renaming kills them, same mechanism as s1), google__gson-1093, fasterxml__jackson-databind-1923

---

### elastic__logstash-16681

**[run-1]** _(42 steps, exit_status: submitted via exit_cost)_
1. The agent's first search is `search_dir "PipelineEventBusV2" .` — a renamed class name from the combined transformation. This returns no results (actual class is `PipelineBusV2`). The follow-up `find . -name "PipelineEventBusV2.java"` also fails.
2. **Critical pivot:** Instead of spiralling in failed class-name searches, the agent switches to method-based searches: `search_dir "unregisterSender" logstash-core` and `search_dir "notifyAll" logstash-core/src/main/java/org/logstash/plugins/pipeline`. These are semantic searches for the specific operations described in the deadlock (unregistering while listeners are active, using notify/wait synchronization). Both succeed and directly point to `PipelineBusV2.java`.
3. This method-based fallback strategy produces **9 edits** — vs s0's 2 and s2's 3. The agent makes a much more thorough fix, addressing multiple synchronization paths rather than just the most obvious one. This thoroughness explains the 5/5 consistency: the more comprehensive fix is robust to the different test-execution orderings across 5 independent runs.
4. 2 test runs confirm the fix works. Despite exit_cost, the submitted patches are correct in all 5 runs.
5. The combined transformation has a paradoxical beneficial effect: the renaming forces the agent to give up on class-name search and fall back to semantic/method search, which finds the real bug more reliably. The structural changes further force re-reading of the synchronization code fresh, preventing pattern-match shortcuts. The result is the most consistent and most thorough fix across all strategies for this instance.

---

### fasterxml__jackson-core-183

**[run-3]** _(48 steps, exit_status: submitted — FEWER steps than s0's 56, 14% more efficient)_
1. **File renamed:** In s4, `TextBuffer.java` becomes `SegmentedTextBuffer.java`. The agent's first search `find_file "SegmentedTextBuffer.java" src` immediately succeeds — the more specific name is easier to target than the generic `TextBuffer`.
2. The rename is semantically meaningful: `SegmentedTextBuffer` explicitly encodes the implementation's segmented-array design. The agent's subsequent exploration of `ParserBase.java` (which uses `SegmentedTextBuffer`) is more targeted because the class name signals its role.
3. 10 edits and 3 test runs. The fix to `getTextBuffer()` is similar to s0 but the agent executes it more efficiently (48 vs 56 steps). The clearer name reduces the "what does this class do?" exploration overhead.
4. This is a case where the rename transformation actually helps rather than hinders: the new name is unambiguous and more descriptive, making the agent's search and navigation more direct.

---

### mockito__mockito-3129

**[run-3]** _(66 steps, exit_status: submitted via exit_cost)_
1. **All names changed:** `MockUtil` → `MockUtilities`, `MockitoPlugins` interface → `MockitoPluginRegistry`, `DefaultMockitoPlugins` → `DefaultMockitoPluginRegistry`. The naming now follows the Registry pattern precisely, making the interface/implementation relationship explicit.
2. The agent searches for `"class MockitoPluginRegistry|interface MockitoPluginRegistry"` in one query — demonstrating it has correctly inferred the new naming convention from the problem statement and can search for both forms simultaneously.
3. 8 searches explore `"getMockMaker"`, `"MockitoPluginRegistry"`, `"getInlineMockMaker"`, and the test file `"MockitoPluginsTest|framework().getPlugins()"`. The method-name searches (`getMockMaker`, `getInlineMockMaker`) are preserved across transformations and serve as stable anchors.
4. 10 edits, 0 test runs. Like s3's mockito trajectory, the agent reasons about correctness statically without test execution. The Registry naming pattern (both interface `MockitoPluginRegistry` and implementation `DefaultMockitoPluginRegistry`) makes the structural relationship unambiguous and reduces cyclic editing.
5. Solved in R3, R4, R5 (3/5). Not as consistent as s1 or s3 (both 4/5), possibly because the combination of renaming + structural moves requires more steps to orient, leaving less budget for iteration.

---

## Cross-Cutting Observations

**1. Class-name anchoring is the primary failure mode under s1/s4:**
Instances that rely on a single class as their entry point (DLQ writer for 14970/14981, JsonWriter for gson-1093, TextBuffer for jackson-core-183) fail completely under renaming when the agent cannot correctly infer the new name from the problem statement. The failure is catastrophic — 4–6 consecutive zero-result searches strand the agent before it can pivot.

**2. Method-name searches are more robust than class-name searches:**
For elastic__logstash-16681 in s4, the switch from class search to method search (`unregisterSender`, `notifyAll`) produces a better fix than the class search used in s0. Instances where agents use method-level searches tend to be more resilient to renaming transformations.

**3. Structural transformation is largely transparent for single-class fixes:**
The DLQ writer instances (14970, 14981) are solved at the same or higher rate under s2 as under s0 because the fix is entirely within one method of one class. Method sorting doesn't change the class name, package, or method signature — the only disruption is line number shifting, which the agent handles by re-reading rather than hard-coding locations.

**4. Problem-statement rewrites have instance-specific effects:**
For mockito-3129, s3 nearly quadruples the success rate (1/5 → 4/5). For gson-1093, it preserves performance (2/5 → 2/5). For elastic__logstash-16579, it unlocks a previously impossible instance. There is no universal direction — the effect depends on whether the original problem statement was the limiting factor.

**5. The combined s4 transformation creates a novel and more reliable search strategy for elastic__logstash-16681:**
The rename breaks the agent's first-choice search strategy, forcing a fallback to semantic method searches. This fallback turns out to be better than the original strategy, producing 9 edits vs s0's 2 and 100% consistency vs s0's 20%. This is the clearest example in the dataset of a metamorphic transformation accidentally improving agent behavior by disrupting an overfit shortcut.

**6. mockito__mockito-3129 is the inverse of the DLQ pattern:**
In s0, the agent cycles through edits in 4 of 5 runs and produces a working fix only once. Under all other strategies, the pass rate improves (4/5 in s1, 2/5 in s2, 4/5 in s3, 3/5 in s4). This pattern is consistent with the agent having a memorized-but-imprecise solution for the original Mockito codebase that it applies incorrectly most of the time. Transformations that change the class names disrupt this shortcut and force genuine step-by-step problem-solving, which is more reliable.
