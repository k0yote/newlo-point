// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title StringsLibraryComparisonTest
 * @author NewLo Team
 * @notice Comparison between custom _uint256ToString and OpenZeppelin Strings library
 * @dev Evaluates functionality, gas efficiency, and safety
 */
contract StringsLibraryComparisonTest is Test {
    /**
     * @notice Custom implementation from DeployMultiTokenDistribution.s.sol
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
     * @notice Test that both implementations produce identical results
     */
    function testIdenticalResults() public view {
        uint[] memory testValues = new uint[](10);
        testValues[0] = 0;
        testValues[1] = 1;
        testValues[2] = 123;
        testValues[3] = 1000;
        testValues[4] = 999999;
        testValues[5] = 10 ** 6;
        testValues[6] = 10 ** 18;
        testValues[7] = 2000 * 10 ** 6; // $2000 USDC
        testValues[8] = 1000000 * 10 ** 6; // $1M USDC
        testValues[9] = type(uint).max;

        for (uint i = 0; i < testValues.length; i++) {
            string memory customResult = _uint256ToString(testValues[i]);
            string memory openzeppelinResult = Strings.toString(testValues[i]);

            assertEq(
                customResult,
                openzeppelinResult,
                string(abi.encodePacked("Mismatch for value: ", Strings.toString(testValues[i])))
            );
        }
    }

    /**
     * @notice Compare gas consumption between implementations
     */
    function testGasComparison() public view {
        uint[] memory testValues = new uint[](4);
        testValues[0] = 123; // Small number
        testValues[1] = 10 ** 18; // 1 ETH
        testValues[2] = 1000000 * 10 ** 6; // $1M USDC
        testValues[3] = type(uint).max; // Maximum value

        console.log("=== Gas Consumption Comparison ===");

        for (uint i = 0; i < testValues.length; i++) {
            uint value = testValues[i];

            // Test custom implementation
            uint gasStart = gasleft();
            _uint256ToString(value);
            uint customGas = gasStart - gasleft();

            // Test OpenZeppelin implementation
            gasStart = gasleft();
            Strings.toString(value);
            uint openzeppelinGas = gasStart - gasleft();

            console.log(
                string(
                    abi.encodePacked(
                        "Value: ",
                        Strings.toString(value),
                        " | Custom: ",
                        Strings.toString(customGas),
                        " gas | OpenZeppelin: ",
                        Strings.toString(openzeppelinGas),
                        " gas | Difference: ",
                        customGas > openzeppelinGas
                            ? string(
                                abi.encodePacked("+", Strings.toString(customGas - openzeppelinGas))
                            )
                            : string(
                                abi.encodePacked("-", Strings.toString(openzeppelinGas - customGas))
                            )
                    )
                )
            );
        }
    }

    /**
     * @notice Fuzz test to ensure both implementations always match
     */
    function testFuzzComparison(uint value) public view {
        string memory customResult = _uint256ToString(value);
        string memory openzeppelinResult = Strings.toString(value);

        assertEq(customResult, openzeppelinResult);
    }

    /**
     * @notice Test with DeFi-specific amounts
     */
    function testDeFiAmounts() public view {
        // Common DeFi amounts
        uint[] memory defiAmounts = new uint[](8);
        defiAmounts[0] = 1 * 10 ** 18; // 1 ETH
        defiAmounts[1] = 100 * 10 ** 18; // 100 ETH
        defiAmounts[2] = 1000 * 10 ** 6; // $1000 USDC
        defiAmounts[3] = 10000 * 10 ** 6; // $10k USDC
        defiAmounts[4] = 1000000 * 10 ** 6; // $1M USDC
        defiAmounts[5] = 5 * 10 ** (18 - 1); // 0.5 ETH
        defiAmounts[6] = 25 * 10 ** (6 - 2); // $0.25 USDC
        defiAmounts[7] = 1; // Smallest unit

        console.log("=== DeFi Amounts Verification ===");

        for (uint i = 0; i < defiAmounts.length; i++) {
            uint amount = defiAmounts[i];
            string memory customResult = _uint256ToString(amount);
            string memory openzeppelinResult = Strings.toString(amount);

            assertEq(customResult, openzeppelinResult);

            console.log(
                string(
                    abi.encodePacked(
                        "Amount: ",
                        openzeppelinResult,
                        " | Results match: ",
                        keccak256(bytes(customResult)) == keccak256(bytes(openzeppelinResult))
                            ? "YES"
                            : "NO"
                    )
                )
            );
        }
    }

    /**
     * @notice Performance stress test
     */
    function testPerformanceStress() public view {
        console.log("=== Performance Stress Test ===");

        uint iterations = 100;
        uint totalCustomGas = 0;
        uint totalOpenzeppelinGas = 0;

        // Test with various sized numbers
        for (uint i = 1; i <= iterations; i++) {
            uint testValue = i * 10 ** 15; // Large numbers

            uint gasStart = gasleft();
            _uint256ToString(testValue);
            totalCustomGas += gasStart - gasleft();

            gasStart = gasleft();
            Strings.toString(testValue);
            totalOpenzeppelinGas += gasStart - gasleft();
        }

        console.log(
            string(
                abi.encodePacked(
                    "Total Custom Gas (",
                    Strings.toString(iterations),
                    " iterations): ",
                    Strings.toString(totalCustomGas)
                )
            )
        );

        console.log(
            string(
                abi.encodePacked(
                    "Total OpenZeppelin Gas (",
                    Strings.toString(iterations),
                    " iterations): ",
                    Strings.toString(totalOpenzeppelinGas)
                )
            )
        );

        console.log(
            string(
                abi.encodePacked(
                    "Average Custom: ",
                    Strings.toString(totalCustomGas / iterations),
                    " | Average OpenZeppelin: ",
                    Strings.toString(totalOpenzeppelinGas / iterations)
                )
            )
        );
    }

    /**
     * @notice Test edge cases where implementations might differ
     */
    function testEdgeCases() public view {
        uint[] memory edgeCases = new uint[](6);
        edgeCases[0] = 0;
        edgeCases[1] = 1;
        edgeCases[2] = 10;
        edgeCases[3] = type(uint8).max; // 255
        edgeCases[4] = type(uint16).max; // 65535
        edgeCases[5] = type(uint).max; // Maximum uint256

        console.log("=== Edge Cases Verification ===");

        for (uint i = 0; i < edgeCases.length; i++) {
            uint value = edgeCases[i];
            string memory customResult = _uint256ToString(value);
            string memory openzeppelinResult = Strings.toString(value);

            bool matches = keccak256(bytes(customResult)) == keccak256(bytes(openzeppelinResult));

            assertTrue(
                matches,
                string(
                    abi.encodePacked(
                        "Edge case failed for value: ",
                        Strings.toString(value),
                        " | Custom: ",
                        customResult,
                        " | OpenZeppelin: ",
                        openzeppelinResult
                    )
                )
            );

            console.log(string(abi.encodePacked("Value: ", openzeppelinResult, " | Match: YES")));
        }
    }
}
