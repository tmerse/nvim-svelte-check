# nvim-svelte-check

A Neovim plugin that runs `svelte-check` asynchronously, displays a spinner while running, and populates the quickfix list with the results.

https://github.com/StephenGunn/sveltecheck.nvim/assets/7240548/99c3549e-2c54-4c1a-ab70-16d463e3e4ad

Inspired by [dmmulroy/tsc.nvim](https://github.com/dmmulroy/tsc.nvim)

## ⚠️ Important: Module Renamed in v2.0.0

The module has been renamed from `sveltecheck` to `svelte-check`. See the [Migration Guide](MIGRATION.md) for details.

## Installation

### Using `lazy.nvim`

1. Ensure `lazy.nvim` is set up in your Neovim configuration.
2. Add the plugin to your plugin list:

```lua
-- lazy.nvim plugin configuration
require('lazy').setup({
    {
        'nvim-svelte/nvim-svelte-check',
        config = function()
            require('svelte-check').setup({
                command = "pnpm run check", -- Default command for pnpm
            })
        end,
    },
})
```

### Using `packer.nvim`

1. Ensure `packer.nvim` is set up in your Neovim configuration.
2. Add the plugin to your plugin list:

```lua
-- packer.nvim plugin configuration
return require('packer').startup(function(use)
    use {
        'nvim-svelte/nvim-svelte-check',
        config = function()
            require('svelte-check').setup({
                command = "pnpm run check", -- Default command for pnpm
            })
        end
    }

    -- Add other plugins as needed
end)
```

## Usage

After installation, run the `svelte-check` command in Neovim:

```vim
:SvelteCheck
```

This command will start the `svelte-check` process, display a spinner, and populate the quickfix list with any errors or warnings found. A summary of the check will be printed upon completion.

## Customization

Customize the plugin by passing configuration options to the `setup` function:

- `command` (string): The command to run `svelte-check` (default: `"pnpm run check"`).
- `spinner_frames` (table): Frames for the spinner animation (default: `{ "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }`)
- `debug_mode` (boolean): Enable debug logging for troubleshooting (default: `false`)

### Example Customization

```lua
require('svelte-check').setup({
    command = "npm run svelte-check", -- Custom command for npm, defaults to pnpm
    spinner_frames = { "⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷" }, -- spinner frames
    debug_mode = false, -- will print debug messages if true (default is false)
})
```

## Troubleshooting

If the plugin isn't correctly detecting errors or warnings:

1. Try enabling debug mode to see detailed logging:

   ```lua
   require('svelte-check').setup({
       command = "npm run check",
       debug_mode = true
   })
   ```

2. Verify that your project's `svelte-check` command works correctly in the terminal
3. Make sure the command in your config matches the exact script name in package.json
4. Check if your project uses a custom output format for svelte-check that might not be compatible with the plugin

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
