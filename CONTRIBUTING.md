To make the lives easier on us maintainers, please help out:

- Be sure to describe what your PR is, and feel free to ask for help along the way.
- Follow the coding style used in other files. Being in the neighborhood is good enough.
- If you're contributing engine-side code, please include specs against the synthetic harness under `spec/support/synthetic/` so the suite stays free of bundled X12 grammars. tediparse does not redistribute X12 IP; transaction-set definitions belong in your own consuming project, not here.
- If you're contributing code (apart from definitions), please include specs so we won't accidentally break your code in the future. Sometimes adding specs won't make sense, or it won't be worth it, so ask if you aren't sure!

Thank you for contributing!
