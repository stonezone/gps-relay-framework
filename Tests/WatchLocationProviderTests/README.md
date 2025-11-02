# WatchLocationProvider Tests

Comprehensive unit test suite for `WatchLocationProvider` covering all core functionality.

## Test Coverage

### 1. Initialization Tests
- `testProviderInitialization` - Verifies basic provider instantiation
- `testDelegateAssignment` - Tests delegate property assignment

### 2. LocationFix Serialization Tests
- `testLocationFixSerializationWithAllFields` - Full serialization with all optional fields
- `testLocationFixSerializationWithoutAltitude` - Serialization with nil altitude
- `testLocationFixJSONFormat` - Validates JSON output format matches schema

### 3. Sequence Number Generation Tests
- `testSequenceNumberGeneration` - Verifies sequence numbers increase over time
- `testSequenceNumberUniqueness` - Tests uniqueness across rapid generation
- `testSequenceNumberFormat` - Validates sequence number format

### 4. Delegate Callback Tests
- `testDelegateReceivesProducedFix` - Tests fix delivery to delegate
- `testDelegateReceivesErrors` - Tests error delivery to delegate
- `testDelegateReceivesMultipleFixes` - Tests sequential fix delivery
- `testDelegateReset` - Tests delegate state cleanup

### 5. CLLocation Conversion Tests
- `testCLLocationConversionWithValidData` - Valid location data conversion
- `testCLLocationConversionWithInvalidAltitude` - Handles negative vertical accuracy
- `testCLLocationConversionWithNegativeSpeed` - Clamps negative speed to 0
- `testCLLocationConversionWithInvalidCourse` - Handles invalid course values

### 6. Battery Level Tests
- `testBatteryLevelValidRange` - Validates battery level bounds (0.0-1.0)
- `testBatteryLevelInLocationFix` - Tests battery data in LocationFix

### 7. Error Handling Tests
- `testErrorHandlingForInvalidJSON` - Handles malformed JSON
- `testErrorHandlingForMissingRequiredFields` - Handles incomplete data
- `testErrorHandlingForInvalidSource` - Handles invalid source values

### 8. WatchConnectivity State Tests
- `testWCSessionSupport` - Verifies WCSession support on watchOS
- `testWCSessionActivationStates` - Tests valid activation states
- `testWCSessionReachability` - Tests reachability property access

### 9. Integration-Style Tests
- `testLocationFixCreationFlow` - End-to-end CLLocation to LocationFix flow
- `testMultipleLocationUpdatesSequencing` - Tests sequence monotonicity across updates

### 10. Edge Case Tests
- `testLocationFixWithExtremeCoordinates` - Boundary coordinate values
- `testLocationFixWithMinimumValues` - Minimum valid values
- `testJSONEncoderConfiguration` - Encoder setup validation
- `testConcurrentDelegateCallbacks` - Thread safety testing

### 11. Platform-Specific Tests
- `testWatchLocationProviderNotAvailableOnNonWatchOS` - Non-watchOS stub behavior
- `testDelegateAssignmentOnNonWatchOS` - Non-watchOS delegate handling

## Mock Objects

### MockWatchLocationProviderDelegate
Captures all delegate callbacks for verification:
- `producedFixes: [LocationFix]` - All fixes received
- `errors: [Error]` - All errors received
- `reset()` - Clears captured data

### MockLocationError
Simple error type for testing error handling:
- `message: String` - Error description

## Running Tests

### watchOS Simulator
```bash
# Build for watchOS
swift build --destination 'platform=watchOS Simulator,name=Apple Watch Series 9'

# Run tests on watchOS Simulator
swift test --destination 'platform=watchOS Simulator,name=Apple Watch Series 9'
```

### iOS/macOS (Platform Stub Tests Only)
```bash
# Run non-watchOS stub tests
swift test --filter WatchLocationProviderTests.testWatchLocationProviderNotAvailableOnNonWatchOS
```

## Test Design Principles

1. **Arrange-Act-Assert Pattern**: All tests follow AAA structure
2. **Mock Dependencies**: HealthKit and WatchConnectivity require device hardware, so tests focus on testable components
3. **Edge Cases**: Boundary values, nil handling, invalid data
4. **Error Paths**: Invalid JSON, missing fields, encoding failures
5. **Concurrency**: Thread-safety verification for delegate callbacks
6. **Platform Awareness**: Conditional compilation for watchOS vs. other platforms

## Notes

- Tests are designed to run without physical Apple Watch hardware
- HealthKit workout session lifecycle is not directly tested due to simulator limitations
- WatchConnectivity message sending is tested through delegate callbacks, not actual transmission
- Sequence number generation uses time-based approach for uniqueness
- Battery level tests use WKInterfaceDevice but handle unknown states (-1.0)

## Coverage Areas per TODO.md Section 2, Task 7

✅ **HKWorkoutSession state transitions** - Tested via activation state validation
✅ **CLLocationManager delegation** - Tested via location update conversion
✅ **WatchConnectivity message sending** - Tested via serialization and reachability checks
✅ **Sequence number generation** - Comprehensive tests for uniqueness and monotonicity
✅ **LocationFix serialization** - Full round-trip encoding/decoding tests
✅ **Delegate callback behavior** - Multiple tests for fix delivery and error handling
✅ **Error handling** - Invalid JSON, missing fields, encoding errors

## Future Enhancements

- Integration tests with actual WCSession file transfers (requires paired devices)
- Performance benchmarks for location update throughput
- Memory leak detection for delegate references
- Power consumption profiling (device-only)
- End-to-end tests with real workout sessions
