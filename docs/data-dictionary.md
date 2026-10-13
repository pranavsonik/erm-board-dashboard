# Data dictionary

All data is simulated. Table names are shown as they appear in Power BI, with the PostgreSQL source in brackets.

## Dimensions

### Risk (`dim_risk`)

| Column | Type | Description |
|---|---|---|
| risk_id | varchar(10) | Primary key, for example R-01 |
| risk_category | varchar(30) | Credit, Operational, Compliance, Third Party, Technology, Liquidity, Market, Strategic or Model |
| risk_title | varchar(150) | Short name of the risk |
| risk_owner | varchar(60) | Accountable executive or manager |
| business_unit | varchar(40) | Lending, Operations, Compliance, IT, Finance or Retail Banking. Used by row-level security |
| date_identified | date | Date the risk was added to the register |

### KRI (`dim_kri`)

| Column | Type | Description |
|---|---|---|
| kri_id | varchar(10) | Primary key, for example K-01 |
| kri_name | varchar(120) | Indicator name, with its unit in brackets: (%) or (#) |
| risk_category | varchar(30) | Risk category the indicator monitors |
| direction | varchar(15) | Whether a higher or a lower value is better |
| green_threshold | numeric(10,2) | Value at which the indicator is within appetite |
| amber_threshold | numeric(10,2) | Value beyond which the indicator is outside appetite |

### Quarter (`dim_quarter`)

| Column | Type | Description |
|---|---|---|
| quarter | varchar(10) | Primary key, for example 2026-Q3 |
| quarter_end | date | Last day of the quarter |
| sort_order | integer | Chronological order, used to sort quarter labels |

## Facts

### Risk Rating (`vw_risk_quarter`)

One row per risk per quarter. Built on `fact_risk_rating`.

| Column | Description |
|---|---|
| risk_id, quarter | Keys to Risk and Quarter |
| inherent_likelihood, inherent_impact | Scores before controls, 1 to 5 |
| residual_likelihood, residual_impact | Scores after controls, 1 to 5 |
| inherent_score | Inherent likelihood × impact |
| residual_score | Residual likelihood × impact |
| control_benefit | Inherent score minus residual score |
| control_effectiveness | Effective or Needs Improvement |
| residual_rating | Critical (15+), High (10 to 14), Medium (5 to 9), Low (1 to 4) |
| rating_order | 1 to 4, used to sort ratings from Critical to Low |
| prior_score | Residual score in the previous quarter |
| direction_of_travel | Increasing, Decreasing, Stable, or New in the first quarter |
| above_appetite | True when residual score is at or above `report_config.risk_appetite_score` |

### KRI Reading (`vw_kri_status`)

One row per indicator per quarter. Built on `fact_kri_value` and `dim_kri`.

| Column | Description |
|---|---|
| kri_id, quarter | Keys to KRI and Quarter |
| actual_value | Measured value for the quarter |
| qoq_change | Change from the previous quarter |
| appetite_status | Within Appetite, Approaching Limit or Outside Appetite |
| Status Order | 1 to 3, added in Power Query to sort the worst status first |

### Action (`vw_action_aging`)

One row per remediation action. Built on `fact_action`, aged against `report_config.as_at_date`.

| Column | Description |
|---|---|
| action_id | Primary key |
| risk_id | Key to Risk |
| action_description | What the action delivers |
| owner, business_unit | Who is accountable |
| priority | High, Medium or Low |
| status | Open, In Progress, Overdue or Closed |
| date_opened, due_date, date_closed | Action dates |
| days_past_due | Days between the due date and the closing date, or the as-at date if still open |
| aging_bucket | Closed, On Track, Overdue 1-30 days, Overdue 31-90 days or Overdue 90+ days |
| Bucket Order | 1 to 5, added in Power Query to sort the aging buckets |

### Incident (`fact_incident`)

One row per loss event.

| Column | Description |
|---|---|
| incident_id | Primary key |
| incident_date | Date of the event |
| quarter | Key to Quarter, derived from incident_date |
| risk_category, business_unit | Where the event occurred |
| severity | Low, Medium, High or Critical |
| estimated_loss | Estimated loss in dollars |
| status | Investigation status |
| root_cause | Primary cause |

## Settings and security

### report_config

A single-row settings table read by the views. Not loaded into Power BI.

| Column | Default | Description |
|---|---|---|
| as_at_date | 2026-09-30 | Reporting date used to age actions |
| risk_appetite_score | 12 | Residual score at or above which a risk is above appetite |

### User Access (`dim_user_access`)

Maps users to the business units they may see. Hidden and not related to other tables; read only by the row-level security role.

| Column | Description |
|---|---|
| user_email | Sign-in name, matched to `USERPRINCIPALNAME()` |
| business_unit | A business unit, or `All` for full access |

## Measures

Every number on the report comes from a measure in the `_Measures` table. Risk and KRI measures use the latest quarter in the current filter context, so they follow the quarter slicer.

| Folder | Measure | Definition |
|---|---|---|
| Risk | As At Quarter | Latest quarter in the current filter context |
| Risk | Total Risks | Distinct risks rated in the quarter |
| Risk | Risks Above Appetite | Risks at or above the appetite score in the quarter |
| Risk | Avg Residual | Average residual score in the quarter |
| Risk | Inherent Score, Residual Score, Control Benefit | Scores in the quarter |
| Risk | Residual Likelihood, Residual Impact | Heat map coordinates in the quarter |
| KRI | KRI Actual | Indicator value in the quarter |
| KRI | KRI QoQ Change | Change from the previous quarter |
| KRI | KRIs Outside Appetite | Indicators outside appetite in the quarter |
| Actions | Open Actions | Actions not closed |
| Actions | Overdue Actions | Actions in any Overdue bucket |
| Actions | Action Count | All actions in the current filter context |
| Actions | Days Overdue | Days overdue for overdue actions, a dash for others |
| Incidents | Total Loss | Sum of estimated loss |
| Incidents | Incident Count | Number of loss events |
| Incidents | Severe Incidents | Events rated High or Critical |
| Key messages | Key Message Risk, Key Message KRI, Key Message Actions | One-sentence summaries for the board page |
| Risk detail | Selected Risk, Selected Risk Profile, Residual Rating, Control Effectiveness, Direction of Travel | Values for the drill-through page and heat map tooltip |
