# Changelog

## [0.2.0](https://github.com/zuqini/zcmp.nvim/compare/v0.1.0...v0.2.0) (2026-09-02)


### Features

* ask the server again as a word grows, behind the lsp provider's ([18d2840](https://github.com/zuqini/zcmp.nvim/commit/18d28408e96a964c6202346002af15e2a422d05b))
* configure Neovim's own completion, in blink.cmp's shape ([b6ab395](https://github.com/zuqini/zcmp.nvim/commit/b6ab3957ba7e957e58bfc4991db2b217b3c5af3b))
* make snippets.preset real, and ship the sources it stands for ([8ee9926](https://github.com/zuqini/zcmp.nvim/commit/8ee992605d7a5e281625661af0df703b612074e2))


### Bug Fixes

* ask 'completeopt' only for flags this Neovim knows ([bd92138](https://github.com/zuqini/zcmp.nvim/commit/bd9213859ce9634dabad6e71c8bc3e2657173915))
* ask the server again on a typed key and nothing else, and give each fact one home ([e1a3cec](https://github.com/zuqini/zcmp.nvim/commit/e1a3cecac37cde97b75566e790f463e3a80fd7c5))
* give everything back on disable(), and survive a config that is wrong ([3ed317b](https://github.com/zuqini/zcmp.nvim/commit/3ed317bb613c5c74f0ccba90d35a63257c0aed8c))
* harden every edge zcmp shares with core -- the fallback route a displaced key takes, the start column a relocated item is put back from, the shapes setup() checks, and the LSP wiring a buffer keeps ([32dc4f2](https://github.com/zuqini/zcmp.nvim/commit/32dc4f290d0e808c3f00e5dd87d74b5c8e69472d))
* **health:** report on the buffer checkhealth was called from ([eaba5a6](https://github.com/zuqini/zcmp.nvim/commit/eaba5a6e2076294bfad83375a72ce0cacad2ae98))
* hold 'autocompletedelay' at 0, so the LSP autotrigger stops taking the ([b034d0c](https://github.com/zuqini/zcmp.nvim/commit/b034d0cd01ecf18b97b41fb254cd6f44ad313e6a))
* reload nothing while disabled, and merge a source list as a list ([4106b99](https://github.com/zuqini/zcmp.nvim/commit/4106b993b508ed214198623d43e51bf2e54ef275))
* stop overriding zsnip's own setup() from the snippets provider ([66663e5](https://github.com/zuqini/zcmp.nvim/commit/66663e52b32ec267bc253495ad209669ffaf00ed))
