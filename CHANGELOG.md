# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial release of TenantPlug
- Core `TenantPlug` module implementing Plug behaviour
- `TenantPlug.Context` for process-local tenant storage
- `TenantPlug.Sources.Behaviour` defining extraction interface
- `TenantPlug.Sources.FromHeader` for HTTP header extraction
- `TenantPlug.Sources.FromSubdomain` for subdomain extraction  
- `TenantPlug.Sources.FromJWT` for JWT token extraction
- `TenantPlug.Logger` for automatic logger metadata integration
- `TenantPlug.Telemetry` for comprehensive observability
- `TenantPlug.TestHelpers` for easy integration testing
- Complete test suite with 95%+ coverage
- Comprehensive documentation and examples

### Features
- Multiple configurable tenant extraction sources
- Automatic logger metadata injection
- Telemetry events for monitoring and observability
- Background job support with context snapshots
- Performance-focused implementation
- Comprehensive error handling
- Process isolation and safety
- Extensive configuration options
- Phoenix and Plug integration
- Test helpers for easy testing

## [0.1.0] - 2024-01-XX

### Added
- Initial implementation
- Core architecture and modules
- Documentation and examples
- Test suite
- CI/CD setup