# Contributing to V-Mouse鼠标映射

Thanks for your interest in contributing! 🎉

## Ways to contribute

### Report bugs or request features
Open an issue in this repository with details about what you experienced or what you would like to see.

### Add support for your Razer mouse
If you have a different Razer mouse model (Naga Trinity, Naga Pro, etc.) and want to help add support:

1. Run the app from Terminal:
   ```bash
   cd /Applications
   './V-Mouse鼠标映射-v0.7.4.app/Contents/MacOS/NagaController'
   ```

2. Press your side buttons and copy the `[HID]` log output

3. Open an issue with:
   - Your mouse model
   - Connection type (USB/Bluetooth/Dongle)
   - The console logs

I'll use this info to add support for your device!

### Code contributions

1. **Fork** the repository
2. **Create a branch** for your changes
3. **Test thoroughly** - especially if adding device support
4. **Submit a pull request** with a clear description of what changed and why

#### Building from source
```bash
bash Scripts/build_app.sh
'./V-Mouse鼠标映射-v0.7.4.app/Contents/MacOS/NagaController' --self-test-hid-codec
```

## Code style

- Follow existing Swift conventions in the project
- Add comments for complex logic
- Keep functions focused and readable

## Questions?

Feel free to open an issue or discussion if you're unsure about anything!

## License

By contributing, you agree that your contribution may be distributed under the repository's combined licensing terms. Do not submit code copied from a project whose license is incompatible with those terms.
