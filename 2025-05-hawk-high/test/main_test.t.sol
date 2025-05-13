// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import {DeployLevelOne} from "../script/DeployLevelOne.s.sol";
import {GraduateToLevelTwo} from "../script/GraduateToLevelTwo.s.sol";
import {LevelOne} from "../src/LevelOne.sol";
import {LevelTwo} from "../src/LevelTwo.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract MainTest is Test {
    DeployLevelOne deployBot;
    GraduateToLevelTwo graduateBot;

    LevelOne levelOneProxy;
    LevelTwo levelTwoImplementation;

    address proxyAddress;
    address levelOneImplementationAddress;
    address levelTwoImplementationAddress;

    MockUSDC usdc;

    address principal;
    uint256 schoolFees;

    // teachers
    address alice;
    address bob;
    // students
    address clara;
    address dan;
    address eli;
    address fin;
    address grey;
    address harriet;
    address[] students;

    function setUp() public {
        deployBot = new DeployLevelOne();
        proxyAddress = deployBot.deployLevelOne();
        levelOneProxy = LevelOne(proxyAddress);

        usdc = deployBot.getUSDC();
        principal = deployBot.principal();
        schoolFees = deployBot.getSchoolFees();
        levelOneImplementationAddress = deployBot.getImplementationAddress();

        alice = makeAddr("first_teacher");
        bob = makeAddr("second_teacher");

        clara = makeAddr("first_student");
        dan = makeAddr("second_student");
        eli = makeAddr("third_student");
        fin = makeAddr("fourth_student");
        grey = makeAddr("fifth_student");
        harriet = makeAddr("six_student");

        students.push(clara);
        students.push(dan);
        students.push(eli);
        students.push(fin);
        students.push(grey);
        students.push(harriet);
        for (uint256 i = 0; i < students.length; i++) {
            vm.label(students[i], string(abi.encodePacked("student", i)));
            usdc.mint(students[i], schoolFees);
        }

        // 学生入学
        _studentsEnrolled();

        vm.label(alice, "teacher1");
        vm.label(bob, "teacher2");
        vm.label(principal, "principal");
    }

    // 校长也可以是老师
    function test_add_principal_to_teacher() public {
        _teachersAdded(alice);
        // 校长也成为老师
        _teachersAdded(principal);

        // 开始会话
        vm.prank(principal);
        levelOneProxy.startSession(60);

        // 过了四周
        vm.warp(block.timestamp + 4 weeks);

        // upgrade
        levelTwoImplementation = new LevelTwo();
        levelTwoImplementationAddress = address(levelTwoImplementation);
        vm.prank(principal);
        levelOneProxy.graduateAndUpgrade(levelTwoImplementationAddress, hex"");
        vm.stopPrank();

        // 在单个老师的情况下，校长获得了40%的学费
        assertGt(usdc.balanceOf(principal), usdc.balanceOf(alice));
    }

    // 对老师分配的代币数量没有除以老师的总量
    function test_error_teacher_fee() public {
        // 添加了三个老师，每个老师分配35%，最终在升级时将revert
        _teachersAdded(alice);
        _teachersAdded(bob);
        _teachersAdded(principal);
        vm.warp(block.timestamp + 4 weeks);

        levelTwoImplementation = new LevelTwo();
        levelTwoImplementationAddress = address(levelTwoImplementation);

        bytes memory data = abi.encodeCall(LevelTwo.graduate, ());

        vm.expectRevert();
        vm.prank(principal);
        levelOneProxy.graduateAndUpgrade(levelTwoImplementationAddress, data);
    }

    // 升级时，缺少对review的检查
    function test_review_count_no_check() public {
        _teachersAdded(alice);
        _teachersAdded(bob);

        // 开始会话
        vm.prank(principal);
        levelOneProxy.startSession(60);

        // 过了四周，中间没有对学生产生任何评分
        vm.warp(block.timestamp + 4 weeks);

        // upgrade
        levelTwoImplementation = new LevelTwo();
        levelTwoImplementationAddress = address(levelTwoImplementation);
        vm.prank(principal);
        levelOneProxy.graduateAndUpgrade(levelTwoImplementationAddress, hex"");
        vm.stopPrank();
    }

    // 缺少对学生review的检查，使得校长可以开除任意学生
    function test_principal_expel_any_student() public {
        // 开始会话
        vm.prank(principal);
        levelOneProxy.startSession(60);
        for (uint256 j = 0; j < 6; j++) {
            vm.prank(principal);
            levelOneProxy.expel(students[j]);
        }

        assertEq(levelOneProxy.getListOfStudents().length, 0);
    }

    function _studentsEnrolled() internal {
        vm.startPrank(clara);
        usdc.approve(address(levelOneProxy), schoolFees);
        levelOneProxy.enroll();
        vm.stopPrank();

        vm.startPrank(dan);
        usdc.approve(address(levelOneProxy), schoolFees);
        levelOneProxy.enroll();
        vm.stopPrank();

        vm.startPrank(eli);
        usdc.approve(address(levelOneProxy), schoolFees);
        levelOneProxy.enroll();
        vm.stopPrank();

        vm.startPrank(fin);
        usdc.approve(address(levelOneProxy), schoolFees);
        levelOneProxy.enroll();
        vm.stopPrank();

        vm.startPrank(grey);
        usdc.approve(address(levelOneProxy), schoolFees);
        levelOneProxy.enroll();
        vm.stopPrank();

        vm.startPrank(harriet);
        usdc.approve(address(levelOneProxy), schoolFees);
        levelOneProxy.enroll();
        vm.stopPrank();
    }

    function _teachersAdded(address _teacher) internal {
        vm.startPrank(principal);
        levelOneProxy.addTeacher(_teacher);
        vm.stopPrank();
    }

    function _studentReview() internal {
        for (uint256 i = 0; i < 4; i++) {
            vm.warp(block.timestamp + 1 weeks);
            for (uint256 j = 0; j < 6; j++) {
                vm.prank(alice);
                levelOneProxy.giveReview(students[j], true);
            }
        }
    }
}
