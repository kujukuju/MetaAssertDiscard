
### Assert Discard Checker

This metaprogram checks that you're not calling any invalid functions inside asserts. You have to pass in function names to be able to call them.

This is because when you eventually disable asserts, it discards the arguments entirely. So any function calls will not exist in the production code.

This can lead to undefined behavior if you're doing some pattern such as `assert(load_and_return_result());`.
