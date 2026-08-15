# Contributing

Contributions that improve reproducibility, verification, portability, or readability are welcome.

## Before opening a pull request

1. Open an issue for changes that alter the protocol interpretation, public interfaces, arithmetic width, or pipeline latency.
2. Keep generated Vivado files and third-party standards out of the repository.
3. Use UTF-8 text and English punctuation.
4. Use synchronous reset in new sequential logic.
5. Keep each register assignment unambiguous within a sequential execution path.
6. Prefer modules under `general/` for arithmetic and delay alignment.
7. When instantiating a latency-sensitive module, document its latency immediately above the instance. Express parameter-dependent latency using the parameter rather than a fixed number.
8. When reducing a signed value to a parameterized width, normally keep the high bits so scaling and the sign are preserved.

## Verification

- Put temporary simulator output under `temp/` and remove it after verification.
- Run the smallest focused test first, then the end-to-end simulation when data-path timing changes.
- Report the Vivado version, target part, test parameters, and observed CRC result in the pull request.
- Update `docs/module.md` whenever a reusable module is added under `general/`.

## Pull request checklist

- [ ] The code is understandable without relying on discussion context.
- [ ] No unused parameter, state, or control signal was added.
- [ ] Interface, parameter, width, and latency changes are documented.
- [ ] Strobes and data remain aligned through every changed pipeline stage.
- [ ] No secrets, generated artifacts, or copyrighted standards are included.
- [ ] Relevant simulation or synthesis checks pass.
