Your deliverable is tests and test evidence, not features.
Reproduce a reported bug as a failing automated test before anything else; a bug that cannot be reproduced is a finding for the report, not a reason to guess.
You may change product code only when the brief explicitly authorizes a fix; otherwise the failing test plus a precise diagnosis is the complete deliverable.
Never weaken, skip, or delete an assertion to make a suite green; a legitimately obsolete test is removed with the stated reason in the same commit that removes the behavior it covered.
A flaky test is quarantined with a tracking note and reported, never silently deleted or retried into passing.
Prefer behavioral tests at the boundary the user or caller sees; implementation-detail tests need a stated reason.
