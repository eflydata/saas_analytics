-- Exploration:

-- How many unique users
SELECT DISTINCT
	COUNT(user_id)
FROM users;
-- There are 1,000 users

-- How many subscriptions?
SELECT
	COUNT(*)
FROM subscriptions;
-- There are 8,424 subscriptions in total
SELECT 
	COUNT (status)
FROM subscriptions
WHERE status = "Active";
-- 8,285 subscriptions are currently active

-- How many payments have been made?
SELECT 
	COUNT(*)
FROM payments;
-- There are 5,393 payments

-- What is the date range of the payment data?
SELECT 
	MIN(payment_date) AS first_payment_date,
    MAX(payment_date) AS last_payment_date
FROM payments;
-- 2023-04-23 through 2025-04-23, a span of two years
-- What is the date range for subscription signups?
SELECT 
	MIN(signup_date) AS first_signup_date,
    MAX(signup_date) AS last_signup_date
FROM users; 
-- This is consistent with the payment date range, 2023-04-23 to 2025-04-22, a span of two years

-- Are there any null values in key columns?
SELECT *
FROM users
WHERE user_id IS NULL OR signup_date IS NULL;

SELECT *
FROM payments
WHERE user_id IS NULL OR payment_date IS NULL or amount_paid_usd IS NULL;

SELECT * 
FROM plans 
WHERE plan_id IS NULL OR plan_name IS NULL;

SELECT * 
FROM subscriptions
WHERE user_id IS NULL OR plan_id IS NULL OR subscription_date IS NULL;
-- There aren't any null values in key columns

-- What distinct plan names exist?
SELECT DISTINCT
	plan_name
FROM plans;
-- The plan names are Free, Starter, Growth, and Enterprise

-- What is the price range for subscriptions?
SELECT
    MIN(monthly_price_usd) AS lowest_priced_plan,
    MAX(monthly_price_usd) AS highest_priced_plan
FROM plans;
-- Plans range from free to $100 per month

-- Cohort Retention Table: Build a monthly cohort retention matrix showing the percentage of users who remain active each month after signup
WITH cohort_items AS (

SELECT 
	user_id,
    DATE_FORMAT(signup_date, '%Y%m') AS cohort_month
FROM users),

user_activity AS (
	SELECT 
	u.user_id,
    DATE_FORMAT(u.signup_date, '%Y%m') AS cohort_month,
    DATE_FORMAT(p.payment_date, '%Y%m') AS activity_month
FROM users AS u
LEFT JOIN payments AS p
ON u.user_id = p.user_id
GROUP BY user_id, cohort_month, activity_month),

cohort_size AS (
SELECT
	cohort_month,
    COUNT(DISTINCT user_id) AS total_users
FROM cohort_items
GROUP BY cohort_month),

cohort_activity AS (
SELECT 
	cohort_month,
    user_id,
    activity_month
FROM user_activity),

retention_data AS (
	SELECT
	cohort_month,
    PERIOD_DIFF (activity_month, cohort_month) AS month_number,
    COUNT(DISTINCT user_id) AS active_user
FROM cohort_activity
GROUP BY cohort_month, month_number)

SELECT 
	rd.cohort_month,
    cz.total_users,
    rd.month_number,
    rd.active_user,
    ROUND(((rd.active_user * 100)/ cz.total_users), 2) AS retention_percentage
FROM retention_data AS rd
LEFT JOIN cohort_size AS cz
ON rd.cohort_month = cz.cohort_month
ORDER BY cohort_month, month_number;

-- Monthly Recurring Revenue (MRR) with Growth: Calculate total MRR, number of paying users, and month-over-month growth rate
WITH monthly_revenue AS (
	SELECT DATE_FORMAT(subscription_date, '%Y-%m') AS subscription_month,
		user_id,
		monthly_revenue_usd
    FROM subscriptions
    WHERE status = "Active"
		AND monthly_revenue_usd <> 0),
        
mrr_aggregation AS (
	SELECT 
		subscription_month,
        SUM(monthly_revenue_usd) AS mrr,
        COUNT(DISTINCT user_id) AS paying_users
	FROM monthly_revenue
    GROUP BY subscription_month),
    
mrr_growth AS (
	SELECT 
		subscription_month,
        mrr,
        paying_users,
        LAG(mrr) OVER (ORDER BY subscription_month) AS previous_month_mrr
	FROM mrr_aggregation)

SELECT
	subscription_month,
    mrr,
    paying_users,
    previous_month_mrr,
    ROUND((((mrr - previous_month_mrr) / previous_month_mrr) * 100), 2) AS growth_percentage
FROM mrr_growth;

-- Churn Risk Segmentation: Classify users into risk segments (High / Medium / Low) based on last activity date, subscription count, and lifetime value
WITH user_metrics AS (
    SELECT 
        u.user_id,
        u.signup_date,
        u.acquisition_channel,
        
        -- Subscription metrics
        COUNT(DISTINCT s.plan_id) AS total_subscriptions,
        COUNT(DISTINCT pl.plan_name) AS unique_plans_tried,
        MAX(s.subscription_date) AS last_subscription_end,
        
        -- Payment metrics
        COUNT(p.payment_date) AS payment_count,
        SUM(p.amount_paid_usd) AS lifetime_value,
        MIN(p.payment_date) AS first_payment_date,
        MAX(p.payment_date) AS last_payment_date,
        
        -- Calculate days since last activity
        DATEDIFF(CURDATE(), MAX(p.payment_date)) AS days_since_last_payment
        
    FROM users u
    LEFT JOIN subscriptions AS s ON u.user_id = s.user_id
    LEFT JOIN payments AS p ON u.user_id = p.user_id
    LEFT JOIN plans AS pl ON pl.plan_id = s.plan_id
    GROUP BY u.user_id, u.signup_date, u.acquisition_channel
),

risk_scoring AS (
    SELECT 
        *,
        
        -- Risk Score Calculation (0-100)
        CASE 
            WHEN days_since_last_payment IS NULL THEN 100  -- Never paid = highest risk
            WHEN days_since_last_payment > 90 THEN 80
            WHEN days_since_last_payment > 60 THEN 60
            WHEN days_since_last_payment > 30 THEN 40
            WHEN days_since_last_payment > 14 THEN 20
            ELSE 0
        END AS recency_score,
        
        CASE 
            WHEN payment_count IS NULL OR payment_count = 0 THEN 100
            WHEN payment_count = 1 THEN 60
            WHEN payment_count <= 3 THEN 30
            ELSE 0
        END AS frequency_score,
        
        CASE 
            WHEN lifetime_value IS NULL OR lifetime_value = 0 THEN 100
            WHEN lifetime_value < 50 THEN 70
            WHEN lifetime_value < 200 THEN 40
            ELSE 0
        END AS monetary_score
        
    FROM user_metrics
),

final_segments AS (
    SELECT 
        *,
        (recency_score + frequency_score + monetary_score) / 3 AS combined_risk_score,
        
        CASE 
            WHEN (recency_score + frequency_score + monetary_score) / 3 >= 70 THEN 'High Churn Risk'
            WHEN (recency_score + frequency_score + monetary_score) / 3 >= 40 THEN 'Medium Churn Risk'
            WHEN (recency_score + frequency_score + monetary_score) / 3 >= 10 THEN 'Low Churn Risk'
            ELSE 'Healthy / Loyal'
        END AS risk_segment
        
    FROM risk_scoring
)

SELECT 
    risk_segment,
    COUNT(*) AS user_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage_of_total,
    ROUND(AVG(lifetime_value), 2) AS avg_ltv,
    ROUND(AVG(payment_count), 1) AS avg_payments,
    ROUND(AVG(days_since_last_payment), 0) AS avg_days_inactive,
    COUNT(CASE WHEN lifetime_value = 0 OR lifetime_value IS NULL THEN 1 END) AS non_paying_users
FROM final_segments
GROUP BY risk_segment
ORDER BY 
    CASE risk_segment
        WHEN 'High Churn Risk' THEN 1
        WHEN 'Medium Churn Risk' THEN 2
        WHEN 'Low Churn Risk' THEN 3
        ELSE 4
    END;
    
    -- Feature Adoption Proxy (Upgrade within 30 days): Identify users who upgraded from Basic to Pro within 30 days of signing up. Treat these as "feature adopters".
    
    -- Conversion Funnel: Count users at each stage:
		-- 1. Signed up
        -- 2. Made first payment
        -- 3. Active for >= 3 months
        -- 4. Upgraded to Pro (if applicable)
	WITH 
-- Stage 1: All signed up users
signed_up AS (
    SELECT 
        user_id,
        signup_date,
        'Signed Up' AS stage,
        1 AS stage_order
    FROM users
),

-- Stage 2: Users who made first payment
first_payment AS (
    SELECT 
        p.user_id,
        p.payment_date AS event_date,
        'Made First Payment' AS stage,
        2 AS stage_order,
        ROW_NUMBER() OVER (PARTITION BY p.user_id ORDER BY p.payment_date) AS payment_rank
    FROM payments p
    WHERE ROW_NUMBER() OVER (PARTITION BY p.user_id ORDER BY p.payment_date) = 1
),

-- Stage 3: Users active for ≥3 months (using payments as proxy)
active_3months AS (
    SELECT 
        p.user_id,
        MAX(p.payment_date) AS event_date,
        'Active ≥3 Months' AS stage,
        3 AS stage_order
    FROM payments p
    GROUP BY p.user_id
    HAVING COUNT(DISTINCT DATE_FORMAT(p.payment_date, '%Y-%m')) >= 3
),

-- Stage 4: Users who upgraded to Pro
upgraded_to_pro AS (
    SELECT 
        s.user_id,
        MIN(s.start_date) AS event_date,
        'Upgraded to Pro' AS stage,
        4 AS stage_order
    FROM subscriptions s
    WHERE s.plan_name LIKE '%Pro%'
    GROUP BY s.user_id
),

-- Combine all stages
funnel_stages AS (
    SELECT user_id, stage, stage_order FROM signed_up
    UNION ALL
    SELECT user_id, stage, stage_order FROM first_payment WHERE payment_rank = 1
    UNION ALL
    SELECT user_id, stage, stage_order FROM active_3months
    UNION ALL
    SELECT user_id, stage, stage_order FROM upgraded_to_pro
),

-- Calculate funnel metrics
funnel_metrics AS (
    SELECT 
        stage,
        stage_order,
        COUNT(DISTINCT user_id) AS users_at_stage
    FROM funnel_stages
    GROUP BY stage, stage_order
),

-- Calculate drop-offs and conversion rates
funnel_with_conversion AS (
    SELECT 
        stage,
        users_at_stage,
        LAG(users_at_stage) OVER (ORDER BY stage_order) AS previous_stage_users,
        
        -- Drop-off from previous stage
        LAG(users_at_stage) OVER (ORDER BY stage_order) - users_at_stage AS drop_off,
        
        -- Conversion rate from previous stage
        ROUND(
            100.0 * users_at_stage / 
            NULLIF(LAG(users_at_stage) OVER (ORDER BY stage_order), 0), 
            2
        ) AS conversion_from_previous,
        
        -- Overall conversion from signup
        ROUND(
            100.0 * users_at_stage / 
            (SELECT COUNT(*) FROM users), 
            2
        ) AS overall_conversion
    FROM funnel_metrics
)

SELECT 
    stage,
    users_at_stage,
    drop_off,
    conversion_from_previous AS conversion_rate_pct,
    overall_conversion AS overall_conversion_pct,
    
    -- Visual bar for conversion (text-based)
    REPEAT('█', CAST(overall_conversion / 2 AS UNSIGNED)) AS visual_bar
    
FROM funnel_with_conversion
ORDER BY stage_order;

-- Bonus: Detailed funnel with user demographics
SELECT 
    'Overall' AS segment,
    COUNT(DISTINCT CASE WHEN stage = 'Signed Up' THEN user_id END) AS signed_up,
    COUNT(DISTINCT CASE WHEN stage = 'Made First Payment' THEN user_id END) AS first_payment,
    COUNT(DISTINCT CASE WHEN stage = 'Active ≥3 Months' THEN user_id END) AS active_3months,
    COUNT(DISTINCT CASE WHEN stage = 'Upgraded to Pro' THEN user_id END) AS upgraded_pro
FROM funnel_stages

UNION ALL

SELECT 
    u.country AS segment,
    COUNT(DISTINCT CASE WHEN fs.stage = 'Signed Up' THEN fs.user_id END) AS signed_up,
    COUNT(DISTINCT CASE WHEN fs.stage = 'Made First Payment' THEN fs.user_id END) AS first_payment,
    COUNT(DISTINCT CASE WHEN fs.stage = 'Active ≥3 Months' THEN fs.user_id END) AS active_3months,
    COUNT(DISTINCT CASE WHEN fs.stage = 'Upgraded to Pro' THEN fs.user_id END) AS upgraded_pro
FROM funnel_stages fs
JOIN users u ON fs.user_id = u.user_id
GROUP BY u.country
ORDER BY signed_up DESC
LIMIT 10;
