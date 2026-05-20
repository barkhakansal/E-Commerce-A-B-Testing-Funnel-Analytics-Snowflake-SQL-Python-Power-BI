# 1. Overview

This project analyzes ecommerce A/B testing performance using customer event, transaction, and campaign data. The objective was to evaluate whether experiment variants improved customer conversion, funnel efficiency, and revenue generation compared to the Control experience.

# 2. Tech Stack
- Snowflake
- SQL
- Python
- Power BI
- SciPy
- Window Functions
- Bronze–Silver–Gold Data Modeling

# 3. Dataset

## Dataset includes:

- 2M+ ecommerce event records
- 100k customer records
- transaction-level purchase data
- marketing campaign metadata
- experiment group assignments

## Main event types:

- view
- click
- add_to_cart
- purchase
- bounce

# 4. Data Architecture
## Bronze Layer

### Raw CSV ingestion:

- events
- customers
- campaigns
- transactions
- products

## Silver Layer

### Cleaned and standardized tables:

- null handling
- timestamp formatting
- deduplication
- consistent data types

## Gold Layer

### Business-ready analytics tables:

- USER_EXPERIMENT_GROUP
- EXPERIMENT_PERFORMANCE
- FUNNEL_RATES
- EXPERIMENT_REVENUE
- CAMPAIGN_PERFORMANCE

# 5. Key Problems Solved
### Experiment Assignment Inconsistency

The dataset stored experiment labels at the event level, causing customers to appear across multiple experiment groups.

### Solution

Created a user-level experiment assignment table using earliest observed experiment exposure via SQL window functions.

### Many-to-Many Join Duplication

Direct joins between event-level and transaction-level tables inflated revenue metrics.

### Solution

Separated event and transaction aggregations into independent summary tables before joining campaign-level metrics.

# 6. Funnel Analysis

Analyzed customer movement through:

View → Click → Add to Cart → Purchase

### Key finding:

- Control group achieved strongest overall funnel conversion
- Variant_A showed highest checkout dropoff
- Variant_B slightly improved revenue per user but did not significantly improve overall funnel performance

# 7. Statistical Testing

Performed chi-square significance testing in Python using SciPy.

### Result:

Neither Variant_A nor Variant_B produced statistically significant improvements over the Control group.

# 8. Key Results
      Metric	              Best Performer
- Conversion Rate	             Variant_B
- Revenue/User	               Variant_B
- Funnel Conversion	           Control

# 9. Final Business Recommendation

Although Variant_B produced slightly higher revenue and conversion metrics, improvements were minimal and not statistically significant.
