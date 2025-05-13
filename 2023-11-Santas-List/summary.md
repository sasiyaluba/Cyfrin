# findings

## high

1. 缺少重入保护，导致的重入攻击

2. 缺少足够的检查，导致用户可以在铸造 nft 后将 nft 转出，而后绕过验证以重复铸造 nft

3. buyPresent 函数中的购买 nft 只需要 1e18，然而文档中说明为 2e18

4. checkList 函数缺少访问控制

5. enum 的顺序存在问题，导致任何用户至少都是 NICE

6. buyPresent 函数中存在错误的代币燃烧逻辑

7. solmate 中存在安全漏洞

8. 该库中的某个测试套件允许用户执行任何指令

## mid

1. checkList 和 checkTwice 函数缺少时间上的访问控制，使得在圣诞节之后依然可以进行 check

## low

1. collectPresent 函数中缺少时间上的访问控制，readme 说明了有 24 小时的时间限制，但是代码中没有体现

2. collectPresent 和 buyPresent 函数中缺少事件释放

3. 0.8.22 版本的 solidity 合约不能部署在 arbitrum 上

4. arbitrum 上的 block.timestamp 是不可信的

## 总结

1. 不要忘记看 lib 中的依赖的版本是否存在问题！！！

2. 对于项目中的测试，也不能忘记检查，对于可能异常的内容不能进行测试，否则有可能导致主机信息泄露

3. enum 这个知识点，注意其第一个值是 0，**因此在作为 mapping 的 value 时**，要特别小心

4. 对于 L2，要注意 solidity 的版本问题，因为 PUSH0 操作码的影响，有些合约不能在 L2 上部署

5. 对于 arbitrum 上的 block.timestamp，要注意其不可信性，可能会导致合约的时间逻辑出现问题

6. modifier 如果只使用一次就没必要了

7. 通过余额判断用户是否提取资金是不安全的，因为余额可以被其余外部操作所控制

8. 只要有 ERC721，就需要特别注意重入的情况

9. 在进行 token -> nft 时，业务逻辑应该是 burn msg.sender 的 token，然后铸造 nft 到 receiver

10. 在看到某个合约中存储了非常长的字符串常量时，需要注意是否会超出合约的大小限制
