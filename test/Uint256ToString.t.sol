// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";

/**
 * @title Uint256ToStringTest
 * @author NewLo Team
 * @notice Test suite to verify the correctness of _uint256ToString function
 * @dev Tests various edge cases and normal cases to ensure the function works properly
 */
contract Uint256ToStringTest is Test {
    /**
     * @notice Copy of the _uint256ToString function from DeployMultiTokenDistribution.s.sol
     * @dev This is a direct copy for testing purposes
     */
    function _uint256ToString(uint value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint temp = value;
        uint digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint8(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @notice Test basic functionality with small numbers
     */
    function testBasicNumbers() public view {
        assertEq(_uint256ToString(0), "0");
        assertEq(_uint256ToString(1), "1");
        assertEq(_uint256ToString(9), "9");
        assertEq(_uint256ToString(10), "10");
        assertEq(_uint256ToString(99), "99");
        assertEq(_uint256ToString(100), "100");
        assertEq(_uint256ToString(123), "123");
        assertEq(_uint256ToString(999), "999");
        assertEq(_uint256ToString(1000), "1000");
    }

    /**
     * @notice Test large numbers
     */
    function testLargeNumbers() public view {
        assertEq(_uint256ToString(1234567890), "1234567890");
        assertEq(_uint256ToString(10 ** 18), "1000000000000000000"); // 1 ETH in wei
        assertEq(_uint256ToString(2000 * 10 ** 6), "2000000000"); // $2000 in USDC units
        assertEq(_uint256ToString(1000000 * 10 ** 6), "1000000000000"); // $1M in USDC units
    }

    /**
     * @notice Test maximum uint256 value
     */
    function testMaxValue() public view {
        uint maxValue = type(uint).max;
        string memory result = _uint256ToString(maxValue);

        // Max uint256 = 2^256 - 1 = 115792089237316195423570985008687907853269984665640564039457584007913129639935
        assertEq(
            result, "115792089237316195423570985008687907853269984665640564039457584007913129639935"
        );
    }

    /**
     * @notice Test powers of 10
     */
    function testPowersOfTen() public view {
        assertEq(_uint256ToString(10 ** 0), "1");
        assertEq(_uint256ToString(10 ** 1), "10");
        assertEq(_uint256ToString(10 ** 2), "100");
        assertEq(_uint256ToString(10 ** 3), "1000");
        assertEq(_uint256ToString(10 ** 6), "1000000");
        assertEq(_uint256ToString(10 ** 9), "1000000000");
        assertEq(_uint256ToString(10 ** 12), "1000000000000");
        assertEq(_uint256ToString(10 ** 15), "1000000000000000");
        assertEq(_uint256ToString(10 ** 18), "1000000000000000000");
    }

    /**
     * @notice Test numbers with repeating digits
     */
    function testRepeatingDigits() public view {
        assertEq(_uint256ToString(111), "111");
        assertEq(_uint256ToString(222), "222");
        assertEq(_uint256ToString(333333), "333333");
        assertEq(_uint256ToString(777777777), "777777777");
        assertEq(_uint256ToString(888888888888), "888888888888");
    }

    /**
     * @notice Test realistic DeFi amounts
     */
    function testDeFiAmounts() public view {
        // Common token amounts
        uint oneETH = 1 * 10 ** 18;
        uint tenETH = 10 * 10 ** 18;
        uint hundredETH = 100 * 10 ** 18;

        assertEq(_uint256ToString(oneETH), "1000000000000000000");
        assertEq(_uint256ToString(tenETH), "10000000000000000000");
        assertEq(_uint256ToString(hundredETH), "100000000000000000000");

        // Stablecoin amounts (6 decimals)
        uint oneUSDC = 1 * 10 ** 6;
        uint thousandUSDC = 1000 * 10 ** 6;
        uint millionUSDC = 1000000 * 10 ** 6;

        assertEq(_uint256ToString(oneUSDC), "1000000");
        assertEq(_uint256ToString(thousandUSDC), "1000000000");
        assertEq(_uint256ToString(millionUSDC), "1000000000000");
    }

    /**
     * @notice Fuzz test to verify function works with random inputs
     */
    function testFuzzConversion(uint value) public view {
        string memory result = _uint256ToString(value);

        // Basic checks
        assertTrue(bytes(result).length > 0);

        // If value is 0, result should be "0"
        if (value == 0) {
            assertEq(result, "0");
        } else {
            // Result should not be "0" for non-zero values
            assertTrue(!_stringsEqual(result, "0"));

            // Result should contain only digits
            bytes memory resultBytes = bytes(result);
            for (uint i = 0; i < resultBytes.length; i++) {
                uint8 char = uint8(resultBytes[i]);
                assertTrue(char >= 48 && char <= 57); // ASCII '0' to '9'
            }
        }
    }

    /**
     * @notice Test gas consumption for different input sizes
     */
    function testGasConsumption() public view {
        uint gasStart;
        uint gasUsed;

        // Test small number
        gasStart = gasleft();
        _uint256ToString(123);
        gasUsed = gasStart - gasleft();
        console.log("Gas for small number (123):", gasUsed);

        // Test large number
        gasStart = gasleft();
        _uint256ToString(10 ** 18);
        gasUsed = gasStart - gasleft();
        console.log("Gas for 1 ETH (10^18):", gasUsed);

        // Test very large number
        gasStart = gasleft();
        _uint256ToString(type(uint).max);
        gasUsed = gasStart - gasleft();
        console.log("Gas for max uint256:", gasUsed);
    }

    /**
     * @notice Helper function to compare strings
     */
    function _stringsEqual(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
