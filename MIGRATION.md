# Migration Guide for nvim-svelte-check

## Migrating from v1.x to v2.x

Version 2.0.0 introduces a module name change from `sveltecheck` to `svelte-check` to match the org naming convention.

### Why the change?

- This plugin is now a part of the nvim-svelte org and we wanted to keep the same naming convention

### How to update your configuration

#### If you're using `lazy.nvim`:

Before:

```lua
require('lazy').setup({
    {
        'nvim-svelte/nvim-svelte-check',
        config = function()
            require('sveltecheck').setup({
                command = "npm run check",
            })
        end,
    },
})
```

After:

```lua
require('lazy').setup({
    {
        'nvim-svelte/nvim-svelte-check',
        config = function()
            require('svelte-check').setup({
                command = "npm run check",
            })
        end,
    },
})
```

#### If you're using `packer.nvim`:

Before:

```lua
use {
    'nvim-svelte/nvim-svelte-check',
    config = function()
        require('sveltecheck').setup({
            command = "npm run check",
        })
    end
}
```

After:

```lua
use {
    'nvim-svelte/nvim-svelte-check',
    config = function()
        require('svelte-check').setup({
            command = "npm run check",
        })
    end
}
```

### Temporary Compatibility

While we recommend updating your configuration to use the new module name, we've included a compatibility layer that will continue to support the old module name for now. You'll receive a warning message encouraging you to update your configuration.

### New Features in v2.x

In addition to the module name change, v2.x includes several improvements:

- More robust error detection
- Better handling of different output formats
- Enhanced debugging capabilities
- Improved documentation
