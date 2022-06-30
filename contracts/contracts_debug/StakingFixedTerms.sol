// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Arrays.sol";


contract StakingFixedTerms is Ownable
{
    using SafeERC20 for IERC20;

    struct StakingProduct
    {
        uint48 duration;
        uint48 end_epoch;
        IERC20 staking_token;
        uint lot_size;
        uint available_lots;
        IERC20 rewards_token;
        uint reward_per_lot;    
    }

    struct SubscriptionDetails
    {
        uint48 begin_epoch;
        address owner;
        uint product_id;
        uint lots;
        uint claimed_rewards;
    }

    mapping (uint => StakingProduct) public products;
    mapping (uint => SubscriptionDetails) public subscriptions;
    uint next_product_id = 1;
    uint next_subscription_id = 1;

    uint curr_epoch;

    constructor()
    { }

    event ProductAdded(uint indexed _product_id, address indexed _staking_token, uint _lot_size, address indexed _rewards_token, uint _reward_per_lot, uint _available_lots, uint48 _duration, uint48 _end_epoch);
    event Subscribed(uint _subscription_id, address indexed _user, uint _begin_epoch, uint indexed _product_id, uint _lots_amount);
    event RewardsClaimed(uint _subscription_id, uint _amount);
    event Withdrawn(uint _subscription_id);

    function addProduct(address staking_token, uint lot_size, address rewards_token, uint reward_per_lot, uint lots_amount, uint48 duration, uint48 end_epoch) public onlyOwner returns(uint)
    {
        require(lot_size > 0, "lot_size must be greater than 0");
        require(reward_per_lot > 0, "reward_per_lot must be greater than 0");
        require(lots_amount > 0, "lots_amount must be greater than 0");
        require(duration > 0, "duration must be greater than 0");
        require(curr_epoch < end_epoch, "end_epoch is in the past");

        IERC20(rewards_token).safeTransferFrom(_msgSender(), address(this), lots_amount*reward_per_lot);
        products[next_product_id] = StakingProduct(duration, end_epoch, IERC20(staking_token), lot_size, lots_amount, IERC20(rewards_token), reward_per_lot);
        emit ProductAdded(next_product_id, staking_token, lot_size, rewards_token, reward_per_lot, lots_amount, duration, end_epoch);
        return next_product_id++;
    }

    function withdrawRewardsToken(uint product_id, address to) public onlyOwner
    {
        require(product_id < next_product_id && product_id > 0, "invalid product_id");
        StakingProduct storage product = products[product_id];
        require(curr_epoch > product.end_epoch, "not finished");
        product.rewards_token.safeTransfer(to, product.available_lots*product.reward_per_lot);
        product.available_lots = 0;
    }

    function subscribe(uint product_id, uint lots_amount) public
    {
        require(product_id < next_product_id && product_id > 0, "invalid product_id");
        StakingProduct storage product = products[product_id];
        require(curr_epoch < product.end_epoch && product.available_lots >= lots_amount, "sold out");

        product.staking_token.safeTransferFrom(_msgSender(), address(this), lots_amount*product.lot_size);
        product.available_lots -= lots_amount;
        subscriptions[next_subscription_id] = SubscriptionDetails((uint48)(curr_epoch), _msgSender(), product_id, lots_amount, 0);     
        emit Subscribed(next_subscription_id, _msgSender(), curr_epoch, product_id, lots_amount);
        next_subscription_id++;
    }

    function availableRewards(uint subscription_id) public view returns(uint)
    {
        SubscriptionDetails memory details = subscriptions[subscription_id];
        if(details.lots != 0)
        {
            // nqkakva logika za tova kolko mu se polaga da vzeme
            // moje da e bazirana na vremeto, tuk sum q slojil naj durvenata: max_reward - claimed_reward
            return products[details.product_id].reward_per_lot*details.lots - details.claimed_rewards;       
        }
        else
            return 0;
    }

    function claimRewards(uint subscription_id, uint amount) public
    {
        require(subscription_id < next_subscription_id && subscription_id > 0, "invalid subscription_id");
        require(amount > 0 && amount <= availableRewards(subscription_id), "invalid amount");
        SubscriptionDetails storage details = subscriptions[subscription_id];
        require(details.owner == _msgSender(), "the caller does not have permissions");
        details.claimed_rewards += amount;
        products[details.product_id].rewards_token.safeTransfer(details.owner, amount);
        emit RewardsClaimed(subscription_id, amount);
    }

    function withdraw(uint subscription_id) public
    {
        require(subscription_id < next_subscription_id && subscription_id > 0, "invalid subscription_id");
        SubscriptionDetails storage details = subscriptions[subscription_id];
        StakingProduct memory product = products[details.product_id];
        require(details.owner == _msgSender(), "the caller does not have permissions");
        require(curr_epoch > details.begin_epoch + product.duration, "lock in period not expired");
            
        uint available_rewards = product.reward_per_lot*details.lots - details.claimed_rewards;
        if(available_rewards > 0)
        {
            products[details.product_id].rewards_token.safeTransfer(details.owner, available_rewards);
            emit RewardsClaimed(subscription_id, available_rewards);
        }
        product.staking_token.safeTransfer(details.owner, product.lot_size*details.lots);
        emit Withdrawn(subscription_id);
        delete subscriptions[subscription_id];
    }

    function setEpoch(uint epoch) public
    {
        curr_epoch = epoch;
    }
    
}
