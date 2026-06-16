# SaaS Analysis

## Project Overview
This music streaming company relies on subscriptions for revenue. Analyzing customer engagement and retention over time is a key aspect of projecting growth and evaluating the success of implemented features and updates. 

## Objective
Evaluate the effectiveness of the new *Collaborative Playlist* feature by evaluating customer engagement from launch through two years. This will inform business decisions for the marketing team. 

##Key Questions
* Did the “Collaborative Playlist” feature (approximated by early upgrade) increase
retention?
* Which user segment has the highest churn risk, and what recommendations can be made to increase engagement for those users?
* What is the current MRR growth trend? Is it accelerating or slowing?

## Tools used
* SQL
* Tableau

## Data Description
The dataset contains information about user sign-up dates, payment dates, plans, and the acquisition channel per user sign-up. It also includes the status of the customer's subscription and which plan they are using. The key attributes include:
* **signup_date**
* **acquisition_channel**: users have been acquired through social media, partnership, paid ads, referral, or organic
* **platform**: Android, iOS, or web users
* **status** in the users table: Refers to the user's current status as churned or active
* **payment_date**
* **amount_paid_usd**: Amount paid each time in US dollars
* **plan_name** and **monthly_price_usd**: There are three plan options and different price points per month in US dollars - Free ($0), Starter ($20), Growth ($50), or Enterprise ($100)
* **status** in the subscriptions table: Refers to the user's current status as active or cancelled. While a user's subscription status may be active for a particular subscription date, the user's status can either be "churned" or "active"
* **subscription_date**: Refers to the date that the user began or changed their subscription
* **monthly_revenue_usd**: Monthly revenue in USD

## Insights


