
# RocketUpdater

**RocketUpdater** is a comprehensive and powerful tool designed to automate the update process of various system utilities and development tools. With RocketUpdater, you can ensure that all your essential tools are always up-to-date, providing you with the latest features and security improvements without the hassle of manual updates.

## Features

- **Homebrew Integration**: Automatically update, upgrade, and clean Homebrew packages.
- **NPM and Yarn Support**: Update global NPM packages and the Yarn version effortlessly.
- **Composer Maintenance**: Clear cache, self-update Composer, and update global Composer packages.
- **Rust Toolchain Updates**: Update Rust toolchains via rustup (and optionally cargo-installed binaries).
- **Conda Environment Management**: Deactivate current Conda environments, update Conda itself, and ensure all environments have the latest Python version and packages.
- **Docker Cleanup**: Remove exited containers and unused images to free up space.
- **macOS Updates**: Keep your macOS up-to-date with the latest software updates.
- **PEAR and PECL Updates**: Clear cache and upgrade PEAR and PECL packages.
- **Additional Utilities**: Update Browsers List with npx.

## Installation

1. Clone the repository:
   ```sh
   git clone https://github.com/BusiRocket/RocketUpdater.git
   ```

2. Navigate to the project directory:
   ```sh
   cd RocketUpdater
   ```

3. Make the script executable:
   ```sh
   chmod +x RocketUpdater.sh
   ```

4. Run the script:
   ```sh
   ./RocketUpdater.sh
   ```

## Usage

Simply execute the `RocketUpdater.sh` script to begin the update process. The script will guide you through updating and cleaning various tools and environments.

## Formatting

Shell scripts are formatted with [shfmt](https://github.com/patrickvane/shfmt). Install it (e.g. `brew install shfmt`), then:

- **Format all scripts:** `./scripts/format.sh`
- **Check only (CI):** `./scripts/format.sh --check`

Indent and style are defined in [.editorconfig](.editorconfig).

## Contributing

We welcome contributions from the community! If you have suggestions for new features or improvements, feel free to open an issue or submit a pull request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
