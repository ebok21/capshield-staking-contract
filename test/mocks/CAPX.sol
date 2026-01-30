// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "solady/src/tokens/ERC20.sol";
import {OwnableRoles} from "solady/src/auth/OwnableRoles.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

interface ICAPX {
    error ZeroAddress();
    error MaxSupplyExceeded();
    error InvalidAmount();
    error InvalidRevenue();
    error InvalidMarketValue();
    error MintAllocationExceeded();
    error AdminMustBeContract();

    event Mint(address indexed to, uint256 amount, uint256 indexed role);
    event RevenueMint(uint256 revenue, uint256 marketValue, uint256 tokensMinted);
    event TreasuryFee(address indexed from, address indexed to, uint256 amount);
    event TreasuryAddressUpdated(address indexed oldTreasury, address indexed newTreasury);
    event DaoAddressUpdated(address indexed oldDao, address indexed newDao);
    event ExemptionUpdated(address indexed account, bool exempt);
    event RoleGranted(uint256 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(uint256 indexed role, address indexed account, address indexed sender);
    event Burn(address indexed from, uint256 amount);

    struct MintAllocation {
        uint256 teamMinted;
        uint256 treasuryMinted;
        uint256 daoMinted;
    }

    function teamMint(address to, uint256 amount) external;

    function treasuryMint(address to, uint256 amount) external;

    function daoMint(address to, uint256 amount) external;

    function revenueMint(address to, uint256 revenue, uint256 marketValue) external;

    function setTreasuryAddress(address newTreasury) external;

    function setDaoAddress(address newDao) external;

    function setExemption(address account, bool exempt) external;

    function pause() external;

    function unpause() external;

    function getTreasuryAddress() external view returns (address);

    function getDaoAddress() external view returns (address);

    function isExempt(address account) external view returns (bool);

    function getMintAllocation() external view returns (MintAllocation memory);

    function getMaxSupply() external pure returns (uint256);
}

contract CAPX is ERC20, OwnableRoles, Pausable, ICAPX {
    uint256 public constant TEAM_MINTER_ROLE = _ROLE_0;
    uint256 public constant TREASURY_MINTER_ROLE = _ROLE_1;
    uint256 public constant DAO_MINTER_ROLE = _ROLE_2;

    uint256 private constant MAX_SUPPLY = 100_000_000 * 10 ** 18;
    uint256 private constant BURN_FEE_PERCENT = 1;
    uint256 private constant TREASURY_FEE_PERCENT = 1;
    uint256 private constant FEE_DENOMINATOR = 100;

    address private treasury;
    address private dao;
    uint256 private totalMinted;

    mapping(address account => bool exempt) private exemptions;

    MintAllocation private mintAllocation;

    constructor(address admin, address _treasury, address _dao) {
        require(admin != address(0), ZeroAddress());
        require(_treasury != address(0), ZeroAddress());
        require(_dao != address(0), ZeroAddress());

        require(_isContract(admin), AdminMustBeContract());

        _initializeOwner(admin);
        _grantRoles(admin, TEAM_MINTER_ROLE | TREASURY_MINTER_ROLE | DAO_MINTER_ROLE);

        treasury = _treasury;
        dao = _dao;

        exemptions[_treasury] = true;
        exemptions[_dao] = true;

        emit TreasuryAddressUpdated(address(0), _treasury);
        emit DaoAddressUpdated(address(0), _dao);
        emit ExemptionUpdated(_treasury, true);
        emit ExemptionUpdated(_dao, true);
        emit RoleGranted(TEAM_MINTER_ROLE, admin, address(0));
        emit RoleGranted(TREASURY_MINTER_ROLE, admin, address(0));
        emit RoleGranted(DAO_MINTER_ROLE, admin, address(0));
    }

    modifier validAddress(address addr) {
        require(addr != address(0), ZeroAddress());
        _;
    }

    modifier validAmount(uint256 amount) {
        require(amount > 0, InvalidAmount());
        _;
    }

    function name() public pure override returns (string memory) {
        return "CAPShield";
    }

    function symbol() public pure override returns (string memory) {
        return "CAPX";
    }

    function teamMint(address to, uint256 amount)
        external
        onlyRoles(TEAM_MINTER_ROLE)
        whenNotPaused
        validAddress(to)
        validAmount(amount)
    {
        require(totalMinted + amount <= MAX_SUPPLY, MaxSupplyExceeded());

        totalMinted = totalMinted + amount;
        mintAllocation.teamMinted = mintAllocation.teamMinted + amount;
        _mint(to, amount);

        emit Mint(to, amount, TEAM_MINTER_ROLE);
    }

    function treasuryMint(address to, uint256 amount)
        external
        onlyRoles(TREASURY_MINTER_ROLE)
        whenNotPaused
        validAddress(to)
        validAmount(amount)
    {
        require(totalMinted + amount <= MAX_SUPPLY, MaxSupplyExceeded());

        totalMinted = totalMinted + amount;
        mintAllocation.treasuryMinted = mintAllocation.treasuryMinted + amount;
        _mint(to, amount);

        emit Mint(to, amount, TREASURY_MINTER_ROLE);
    }

    function daoMint(address to, uint256 amount)
        external
        onlyRoles(DAO_MINTER_ROLE)
        whenNotPaused
        validAddress(to)
        validAmount(amount)
    {
        require(totalMinted + amount <= MAX_SUPPLY, MaxSupplyExceeded());

        totalMinted = totalMinted + amount;
        mintAllocation.daoMinted = mintAllocation.daoMinted + amount;
        _mint(to, amount);

        emit Mint(to, amount, DAO_MINTER_ROLE);
    }

    function revenueMint(address to, uint256 revenue, uint256 marketValue)
        external
        onlyOwner
        whenNotPaused
        validAddress(to)
    {
        require(revenue > 0, InvalidRevenue());
        require(marketValue > 0, InvalidMarketValue());

        uint256 tokensToMint = (revenue * 10 ** decimals()) / marketValue;
        require(tokensToMint > 0, InvalidAmount());
        require(totalMinted + tokensToMint <= MAX_SUPPLY, MaxSupplyExceeded());

        totalMinted = totalMinted + tokensToMint;
        _mint(to, tokensToMint);

        emit RevenueMint(revenue, marketValue, tokensToMint);
    }

    function setTreasuryAddress(address newTreasury) external onlyOwner validAddress(newTreasury) {
        address oldTreasury = treasury;
        treasury = newTreasury;

        exemptions[oldTreasury] = false;
        exemptions[newTreasury] = true;

        emit TreasuryAddressUpdated(oldTreasury, newTreasury);
        emit ExemptionUpdated(oldTreasury, false);
        emit ExemptionUpdated(newTreasury, true);
    }

    function setDaoAddress(address newDao) external onlyOwner validAddress(newDao) {
        address oldDao = dao;
        dao = newDao;

        exemptions[oldDao] = false;
        exemptions[newDao] = true;

        emit DaoAddressUpdated(oldDao, newDao);
        emit ExemptionUpdated(oldDao, false);
        emit ExemptionUpdated(newDao, true);
    }

    function setExemption(address account, bool exempt) external onlyOwner validAddress(account) {
        exemptions[account] = exempt;
        emit ExemptionUpdated(account, exempt);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function transfer(address to, uint256 amount) public override whenNotPaused returns (bool) {
        _applyTransferWithFees(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override whenNotPaused returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _applyTransferWithFees(from, to, amount);
        return true;
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
        emit Burn(msg.sender, amount);
    }

    function burnFrom(address from, uint256 amount) external {
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
        emit Burn(from, amount);
    }

    function grantRoles(address user, uint256 roles) public payable override onlyOwner {
        super.grantRoles(user, roles);
        emit RoleGranted(roles, user, msg.sender);
    }

    function revokeRoles(address user, uint256 roles) public payable override onlyOwner {
        super.revokeRoles(user, roles);
        emit RoleRevoked(roles, user, msg.sender);
    }

    function transferOwnership(address newOwner) public payable override onlyOwner {
        require(_isContract(newOwner), AdminMustBeContract());
        super.transferOwnership(newOwner);
    }

    function completeOwnershipHandover(address pendingOwner) public payable override onlyOwner {
        require(_isContract(pendingOwner), AdminMustBeContract());
        super.completeOwnershipHandover(pendingOwner);
    }

    function renounceOwnership() public payable override onlyOwner {
        revert("Ownership cannot be renounced");
    }

    function getTreasuryAddress() external view returns (address) {
        return treasury;
    }

    function getDaoAddress() external view returns (address) {
        return dao;
    }

    function isExempt(address account) external view returns (bool) {
        return exemptions[account];
    }

    function getMintAllocation() external view returns (MintAllocation memory) {
        return mintAllocation;
    }

    function getMaxSupply() external pure returns (uint256) {
        return MAX_SUPPLY;
    }

    function hasRole(uint256 role, address user) external view returns (bool) {
        return hasAllRoles(user, role);
    }

    function DEFAULT_ADMIN_ROLE() external pure returns (bytes32) {
        return bytes32(0);
    }

    function isOwnerMultisig() external view returns (bool) {
        return _isContract(owner());
    }

    function _isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function _applyTransferWithFees(address from, address to, uint256 amount) internal {
        require(from != address(0), ZeroAddress());
        require(to != address(0), ZeroAddress());
        require(amount > 0, InvalidAmount());

        if (exemptions[from] || exemptions[to]) {
            super._transfer(from, to, amount);
        } else {
            uint256 burnAmount = (amount * BURN_FEE_PERCENT) / FEE_DENOMINATOR;
            uint256 treasuryAmount = (amount * TREASURY_FEE_PERCENT) / FEE_DENOMINATOR;
            uint256 recipientAmount = amount - burnAmount - treasuryAmount;

            if (burnAmount > 0) {
                _burn(from, burnAmount);
            }

            if (treasuryAmount > 0) {
                super._transfer(from, treasury, treasuryAmount);
                emit TreasuryFee(from, treasury, treasuryAmount);
            }

            super._transfer(from, to, recipientAmount);
        }
    }
}
