--
-- PostgreSQL database dump
--

-- Dumped from database version 17.5
-- Dumped by pg_dump version 17.5

-- Started on 2026-10-12 22:21:11

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- TOC entry 220 (class 1259 OID 25603)
-- Name: dim_kri; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dim_kri (
    kri_id character varying(10) NOT NULL,
    kri_name character varying(120),
    risk_category character varying(30),
    direction character varying(15),
    green_threshold numeric(10,2),
    amber_threshold numeric(10,2)
);


--
-- TOC entry 217 (class 1259 OID 25578)
-- Name: dim_quarter; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dim_quarter (
    quarter character varying(10) NOT NULL,
    quarter_end date NOT NULL,
    sort_order integer NOT NULL
);


--
-- TOC entry 218 (class 1259 OID 25583)
-- Name: dim_risk; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dim_risk (
    risk_id character varying(10) NOT NULL,
    risk_category character varying(30) NOT NULL,
    risk_title character varying(150) NOT NULL,
    risk_owner character varying(60),
    business_unit character varying(40),
    date_identified date
);


--
-- TOC entry 230 (class 1259 OID 33857)
-- Name: dim_user_access; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dim_user_access (
    user_email character varying(120) NOT NULL,
    business_unit character varying(40) NOT NULL
);


--
-- TOC entry 222 (class 1259 OID 25623)
-- Name: fact_action; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_action (
    action_id character varying(10) NOT NULL,
    risk_id character varying(10),
    action_description character varying(200),
    owner character varying(60),
    business_unit character varying(40),
    date_opened date,
    due_date date,
    date_closed date,
    status character varying(20),
    priority character varying(10)
);


--
-- TOC entry 223 (class 1259 OID 25633)
-- Name: fact_incident; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_incident (
    incident_id character varying(10) NOT NULL,
    incident_date date,
    risk_category character varying(30),
    business_unit character varying(40),
    severity character varying(15),
    estimated_loss numeric(12,2),
    status character varying(20),
    root_cause character varying(60),
    quarter character varying(10)
);


--
-- TOC entry 221 (class 1259 OID 25608)
-- Name: fact_kri_value; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_kri_value (
    kri_id character varying(10) NOT NULL,
    quarter character varying(10) NOT NULL,
    actual_value numeric(10,2)
);


--
-- TOC entry 219 (class 1259 OID 25588)
-- Name: fact_risk_rating; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fact_risk_rating (
    risk_id character varying(10) NOT NULL,
    quarter character varying(10) NOT NULL,
    quarter_end date,
    inherent_likelihood smallint,
    inherent_impact smallint,
    control_effectiveness character varying(20),
    residual_likelihood smallint,
    residual_impact smallint
);


--
-- TOC entry 228 (class 1259 OID 25664)
-- Name: report_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.report_config (
    id boolean DEFAULT true NOT NULL,
    as_at_date date NOT NULL,
    risk_appetite_score integer DEFAULT 12 NOT NULL,
    CONSTRAINT report_config_id_check CHECK (id)
);


--
-- TOC entry 227 (class 1259 OID 25653)
-- Name: vw_action_aging; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_action_aging AS
 SELECT a.action_id,
    a.risk_id,
    d.risk_title,
    d.risk_category,
    a.owner,
    a.business_unit,
    a.priority,
    a.status,
    a.date_opened,
    a.due_date,
    a.date_closed,
    (COALESCE(a.date_closed, c.as_at_date) - a.due_date) AS days_past_due,
        CASE
            WHEN ((a.status)::text = 'Closed'::text) THEN 'Closed'::text
            WHEN ((c.as_at_date - a.due_date) <= 0) THEN 'On Track'::text
            WHEN ((c.as_at_date - a.due_date) <= 30) THEN 'Overdue 1-30 days'::text
            WHEN ((c.as_at_date - a.due_date) <= 90) THEN 'Overdue 31-90 days'::text
            ELSE 'Overdue 90+ days'::text
        END AS aging_bucket,
    a.action_description
   FROM ((public.fact_action a
     LEFT JOIN public.dim_risk d ON (((d.risk_id)::text = (a.risk_id)::text)))
     CROSS JOIN public.report_config c);


--
-- TOC entry 226 (class 1259 OID 25648)
-- Name: vw_kri_status; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_kri_status AS
 SELECT v.kri_id,
    k.kri_name,
    k.risk_category,
    v.quarter,
    q.sort_order,
    v.actual_value,
    k.green_threshold,
    k.amber_threshold,
    k.direction,
        CASE
            WHEN ((k.direction)::text = 'higher_better'::text) THEN
            CASE
                WHEN (v.actual_value >= k.green_threshold) THEN 'Within Appetite'::text
                WHEN (v.actual_value >= k.amber_threshold) THEN 'Approaching Limit'::text
                ELSE 'Outside Appetite'::text
            END
            ELSE
            CASE
                WHEN (v.actual_value <= k.green_threshold) THEN 'Within Appetite'::text
                WHEN (v.actual_value <= k.amber_threshold) THEN 'Approaching Limit'::text
                ELSE 'Outside Appetite'::text
            END
        END AS appetite_status,
    (v.actual_value - lag(v.actual_value) OVER (PARTITION BY v.kri_id ORDER BY q.sort_order)) AS qoq_change
   FROM ((public.fact_kri_value v
     JOIN public.dim_kri k ON (((k.kri_id)::text = (v.kri_id)::text)))
     JOIN public.dim_quarter q ON (((q.quarter)::text = (v.quarter)::text)));


--
-- TOC entry 229 (class 1259 OID 25678)
-- Name: vw_risk_quarter; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_risk_quarter AS
 WITH scored AS (
         SELECT r.risk_id,
            r.quarter,
            q.sort_order,
            r.inherent_likelihood,
            r.inherent_impact,
            r.residual_likelihood,
            r.residual_impact,
            r.control_effectiveness,
            (r.inherent_likelihood * r.inherent_impact) AS inherent_score,
            (r.residual_likelihood * r.residual_impact) AS residual_score
           FROM (public.fact_risk_rating r
             JOIN public.dim_quarter q ON (((q.quarter)::text = (r.quarter)::text)))
        ), with_prior AS (
         SELECT s.risk_id,
            s.quarter,
            s.sort_order,
            s.inherent_likelihood,
            s.inherent_impact,
            s.residual_likelihood,
            s.residual_impact,
            s.control_effectiveness,
            s.inherent_score,
            s.residual_score,
            lag(s.residual_score) OVER (PARTITION BY s.risk_id ORDER BY s.sort_order) AS prior_score
           FROM scored s
        )
 SELECT p.risk_id,
    p.quarter,
    p.inherent_likelihood,
    p.inherent_impact,
    p.residual_likelihood,
    p.residual_impact,
    p.inherent_score,
    p.residual_score,
    (p.inherent_score - p.residual_score) AS control_benefit,
    p.control_effectiveness,
        CASE
            WHEN (p.residual_score >= 15) THEN 'Critical'::text
            WHEN (p.residual_score >= 10) THEN 'High'::text
            WHEN (p.residual_score >= 5) THEN 'Medium'::text
            ELSE 'Low'::text
        END AS residual_rating,
        CASE
            WHEN (p.residual_score >= 15) THEN 1
            WHEN (p.residual_score >= 10) THEN 2
            WHEN (p.residual_score >= 5) THEN 3
            ELSE 4
        END AS rating_order,
    p.prior_score,
        CASE
            WHEN (p.prior_score IS NULL) THEN 'New'::text
            WHEN (p.residual_score > p.prior_score) THEN 'Increasing'::text
            WHEN (p.residual_score < p.prior_score) THEN 'Decreasing'::text
            ELSE 'Stable'::text
        END AS direction_of_travel,
    (p.residual_score >= c.risk_appetite_score) AS above_appetite
   FROM (with_prior p
     CROSS JOIN public.report_config c);


--
-- TOC entry 224 (class 1259 OID 25638)
-- Name: vw_risk_register; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_risk_register AS
 WITH ranked AS (
         SELECT r.risk_id,
            r.quarter,
            r.quarter_end,
            r.inherent_likelihood,
            r.inherent_impact,
            r.control_effectiveness,
            r.residual_likelihood,
            r.residual_impact,
            q.sort_order,
            row_number() OVER (PARTITION BY r.risk_id ORDER BY q.sort_order DESC) AS rn
           FROM (public.fact_risk_rating r
             JOIN public.dim_quarter q ON (((q.quarter)::text = (r.quarter)::text)))
        )
 SELECT d.risk_id,
    d.risk_category,
    d.risk_title,
    d.risk_owner,
    d.business_unit,
    k.quarter,
    (k.inherent_likelihood * k.inherent_impact) AS inherent_score,
    (k.residual_likelihood * k.residual_impact) AS residual_score,
    ((k.inherent_likelihood * k.inherent_impact) - (k.residual_likelihood * k.residual_impact)) AS control_benefit,
    k.control_effectiveness,
        CASE
            WHEN ((k.residual_likelihood * k.residual_impact) >= 15) THEN 'Critical'::text
            WHEN ((k.residual_likelihood * k.residual_impact) >= 10) THEN 'High'::text
            WHEN ((k.residual_likelihood * k.residual_impact) >= 5) THEN 'Medium'::text
            ELSE 'Low'::text
        END AS residual_rating
   FROM (ranked k
     JOIN public.dim_risk d ON (((d.risk_id)::text = (k.risk_id)::text)))
  WHERE (k.rn = 1);


--
-- TOC entry 225 (class 1259 OID 25643)
-- Name: vw_risk_trend; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_risk_trend AS
 SELECT r.risk_id,
    d.risk_title,
    d.risk_category,
    r.quarter,
    q.sort_order,
    (r.residual_likelihood * r.residual_impact) AS residual_score,
    lag((r.residual_likelihood * r.residual_impact)) OVER (PARTITION BY r.risk_id ORDER BY q.sort_order) AS prior_score,
        CASE
            WHEN (lag((r.residual_likelihood * r.residual_impact)) OVER (PARTITION BY r.risk_id ORDER BY q.sort_order) IS NULL) THEN 'New'::text
            WHEN ((r.residual_likelihood * r.residual_impact) > lag((r.residual_likelihood * r.residual_impact)) OVER (PARTITION BY r.risk_id ORDER BY q.sort_order)) THEN 'Increasing'::text
            WHEN ((r.residual_likelihood * r.residual_impact) < lag((r.residual_likelihood * r.residual_impact)) OVER (PARTITION BY r.risk_id ORDER BY q.sort_order)) THEN 'Decreasing'::text
            ELSE 'Stable'::text
        END AS direction_of_travel
   FROM ((public.fact_risk_rating r
     JOIN public.dim_risk d ON (((d.risk_id)::text = (r.risk_id)::text)))
     JOIN public.dim_quarter q ON (((q.quarter)::text = (r.quarter)::text)));


--
-- TOC entry 4973 (class 0 OID 25603)
-- Dependencies: 220
-- Data for Name: dim_kri; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.dim_kri VALUES ('K-01', 'AML ongoing monitoring reviews completed on time (%)', 'Compliance', 'higher_better', 95.00, 90.00);
INSERT INTO public.dim_kri VALUES ('K-02', 'High-risk members reviewed within policy timeframe (%)', 'Compliance', 'higher_better', 100.00, 95.00);
INSERT INTO public.dim_kri VALUES ('K-03', 'Loan delinquency 30+ DPD (%)', 'Credit', 'lower_better', 1.50, 2.50);
INSERT INTO public.dim_kri VALUES ('K-04', 'Non-performing loan ratio (%)', 'Credit', 'lower_better', 1.00, 2.00);
INSERT INTO public.dim_kri VALUES ('K-05', 'Operational incidents per quarter (#)', 'Operational', 'lower_better', 8.00, 15.00);
INSERT INTO public.dim_kri VALUES ('K-06', 'Critical vendor assessments current (%)', 'Third Party', 'higher_better', 90.00, 80.00);
INSERT INTO public.dim_kri VALUES ('K-07', 'Liquidity coverage ratio (%)', 'Liquidity', 'higher_better', 120.00, 110.00);
INSERT INTO public.dim_kri VALUES ('K-09', 'Staff completing annual risk/AML training (%)', 'Compliance', 'higher_better', 95.00, 90.00);
INSERT INTO public.dim_kri VALUES ('K-08', 'Internal audit findings past due (#)', 'Operational', 'lower_better', 5.00, 10.00);


--
-- TOC entry 4970 (class 0 OID 25578)
-- Dependencies: 217
-- Data for Name: dim_quarter; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.dim_quarter VALUES ('2024-Q4', '2024-12-31', 1);
INSERT INTO public.dim_quarter VALUES ('2025-Q1', '2025-03-31', 2);
INSERT INTO public.dim_quarter VALUES ('2025-Q2', '2025-06-30', 3);
INSERT INTO public.dim_quarter VALUES ('2025-Q3', '2025-09-30', 4);
INSERT INTO public.dim_quarter VALUES ('2025-Q4', '2025-12-31', 5);
INSERT INTO public.dim_quarter VALUES ('2026-Q1', '2026-03-31', 6);
INSERT INTO public.dim_quarter VALUES ('2026-Q2', '2026-06-30', 7);
INSERT INTO public.dim_quarter VALUES ('2026-Q3', '2026-09-30', 8);


--
-- TOC entry 4971 (class 0 OID 25583)
-- Dependencies: 218
-- Data for Name: dim_risk; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.dim_risk VALUES ('R-01', 'Credit', 'Residential mortgage default concentration', 'VP Lending', 'Lending', '2024-04-24');
INSERT INTO public.dim_risk VALUES ('R-02', 'Credit', 'Commercial loan portfolio deterioration', 'VP Lending', 'Lending', '2024-01-26');
INSERT INTO public.dim_risk VALUES ('R-03', 'Credit', 'HELOC utilization and repayment shock', 'Manager, Credit', 'Lending', '2024-10-08');
INSERT INTO public.dim_risk VALUES ('R-04', 'Operational', 'Manual process error in account onboarding', 'Manager, Operations', 'Operations', '2024-09-07');
INSERT INTO public.dim_risk VALUES ('R-05', 'Operational', 'Key person dependency in core banking ops', 'COO', 'Operations', '2024-08-16');
INSERT INTO public.dim_risk VALUES ('R-08', 'Third Party', 'Core banking vendor concentration', 'CIO', 'IT', '2025-07-12');
INSERT INTO public.dim_risk VALUES ('R-09', 'Third Party', 'Critical vendor exit / continuity planning', 'CIO', 'IT', '2024-03-30');
INSERT INTO public.dim_risk VALUES ('R-10', 'Technology', 'Cyber incident / ransomware exposure', 'CIO', 'IT', '2025-03-08');
INSERT INTO public.dim_risk VALUES ('R-11', 'Liquidity', 'Deposit run-off under stress scenario', 'CFO', 'Finance', '2024-02-02');
INSERT INTO public.dim_risk VALUES ('R-12', 'Market', 'Interest rate repricing mismatch', 'CFO', 'Finance', '2024-01-31');
INSERT INTO public.dim_risk VALUES ('R-13', 'Strategic', 'Member attrition to digital-first competitors', 'CEO', 'Retail Banking', '2024-04-05');
INSERT INTO public.dim_risk VALUES ('R-14', 'Model', 'Model governance and validation coverage', 'CFO', 'Finance', '2024-08-11');
INSERT INTO public.dim_risk VALUES ('R-06', 'Compliance', 'AML transaction monitoring effectiveness', 'Chief Compliance Officer', 'Compliance', '2024-05-22');
INSERT INTO public.dim_risk VALUES ('R-07', 'Compliance', 'Member due diligence and record-keeping quality', 'Chief Compliance Officer', 'Compliance', '2024-04-14');


--
-- TOC entry 4978 (class 0 OID 33857)
-- Dependencies: 230
-- Data for Name: dim_user_access; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.dim_user_access VALUES ('cro@example.com', 'All');
INSERT INTO public.dim_user_access VALUES ('lending.manager@example.com', 'Lending');
INSERT INTO public.dim_user_access VALUES ('ops.manager@example.com', 'Operations');
INSERT INTO public.dim_user_access VALUES ('compliance.officer@example.com', 'Compliance');
INSERT INTO public.dim_user_access VALUES ('it.manager@example.com', 'IT');
INSERT INTO public.dim_user_access VALUES ('finance.manager@example.com', 'Finance');
INSERT INTO public.dim_user_access VALUES ('retail.manager@example.com', 'Retail Banking');


--
-- TOC entry 4975 (class 0 OID 25623)
-- Dependencies: 222
-- Data for Name: fact_action; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.fact_action VALUES ('A-015', 'R-03', 'Introduce utilization alerts for high-balance HELOCs - follow-up review', 'Manager, Credit', 'Lending', '2025-12-07', '2026-04-06', '2026-03-10', 'Closed', 'Low');
INSERT INTO public.fact_action VALUES ('A-044', 'R-10', 'Complete ransomware tabletop exercise - follow-up review', 'CIO', 'IT', '2026-06-01', '2026-09-29', '2026-09-12', 'Closed', 'Medium');
INSERT INTO public.fact_action VALUES ('A-043', 'R-11', 'Diversify wholesale funding sources - follow-up review', 'CFO', 'Finance', '2026-06-28', '2026-12-25', '2026-11-25', 'Closed', 'Medium');
INSERT INTO public.fact_action VALUES ('A-033', 'R-13', 'Review member pricing against digital competitors - follow-up review', 'CEO', 'Retail Banking', '2026-08-17', '2027-02-13', '2027-01-30', 'Closed', 'Medium');
INSERT INTO public.fact_action VALUES ('A-046', 'R-14', 'Update model inventory and ownership - follow-up review', 'CFO', 'Finance', '2025-10-11', '2026-04-09', '2026-04-02', 'Closed', 'Medium');
INSERT INTO public.fact_action VALUES ('A-013', 'R-14', 'Document model performance monitoring - follow-up review', 'CFO', 'Finance', '2026-02-21', '2026-08-20', '2026-07-22', 'Closed', 'High');
INSERT INTO public.fact_action VALUES ('A-035', 'R-03', 'Update HELOC renewal criteria', 'Manager, Credit', 'Lending', '2025-03-28', '2025-06-26', '2025-06-06', 'Closed', 'Low');
INSERT INTO public.fact_action VALUES ('A-036', 'R-06', 'Tune transaction monitoring alert thresholds', 'Chief Compliance Officer', 'Compliance', '2025-04-06', '2025-06-05', '2025-05-29', 'Closed', 'High');
INSERT INTO public.fact_action VALUES ('A-028', 'R-06', 'Independent test of AML monitoring programme', 'Chief Compliance Officer', 'Compliance', '2025-11-18', '2025-12-18', '2025-12-09', 'Closed', 'Low');
INSERT INTO public.fact_action VALUES ('A-034', 'R-08', 'Negotiate exit and transition clauses with vendor', 'CIO', 'IT', '2025-08-07', '2026-02-03', '2026-01-06', 'Closed', 'Low');
INSERT INTO public.fact_action VALUES ('A-039', 'R-10', 'Test offline backup restoration', 'CIO', 'IT', '2025-07-19', '2025-11-16', '2025-11-09', 'Closed', 'High');
INSERT INTO public.fact_action VALUES ('A-040', 'R-11', 'Update contingency funding plan', 'CFO', 'Finance', '2025-01-06', '2025-02-05', '2025-01-29', 'Closed', 'High');
INSERT INTO public.fact_action VALUES ('A-031', 'R-11', 'Run deposit run-off stress scenario', 'CFO', 'Finance', '2025-06-28', '2025-12-25', '2025-12-13', 'Closed', 'Low');
INSERT INTO public.fact_action VALUES ('A-004', 'R-12', 'Review ALCO repricing gap limits', 'CFO', 'Finance', '2025-12-18', '2026-02-16', '2026-01-20', 'Closed', 'Medium');
INSERT INTO public.fact_action VALUES ('A-024', 'R-13', 'Analyse member attrition by segment', 'CEO', 'Retail Banking', '2025-11-18', '2026-03-18', '2026-03-02', 'Closed', 'High');
INSERT INTO public.fact_action VALUES ('A-002', 'R-03', 'Run payment shock analysis on HELOC portfolio - follow-up review', 'Manager, Credit', 'Lending', '2025-09-28', '2026-10-23', NULL, 'In Progress', 'Low');
INSERT INTO public.fact_action VALUES ('A-045', 'R-03', 'Update HELOC renewal criteria - follow-up review', 'Manager, Credit', 'Lending', '2026-05-02', '2027-01-15', NULL, 'Open', 'High');
INSERT INTO public.fact_action VALUES ('A-023', 'R-01', 'Review mortgage concentration limits by region', 'VP Lending', 'Lending', '2025-04-22', '2026-10-11', NULL, 'In Progress', 'Low');
INSERT INTO public.fact_action VALUES ('A-017', 'R-02', 'Complete annual review of commercial watchlist', 'VP Lending', 'Lending', '2026-01-27', '2026-11-22', NULL, 'Open', 'High');
INSERT INTO public.fact_action VALUES ('A-006', 'R-02', 'Strengthen covenant monitoring for commercial loans', 'VP Lending', 'Lending', '2026-03-10', '2026-12-10', NULL, 'Open', 'Medium');
INSERT INTO public.fact_action VALUES ('A-037', 'R-03', 'Run payment shock analysis on HELOC portfolio', 'Manager, Credit', 'Lending', '2025-01-26', '2026-04-28', NULL, 'Overdue', 'Medium');
INSERT INTO public.fact_action VALUES ('A-059', 'R-03', 'Introduce utilization alerts for high-balance HELOCs', 'Manager, Credit', 'Lending', '2025-02-21', '2026-07-09', NULL, 'Overdue', 'High');
INSERT INTO public.fact_action VALUES ('A-019', 'R-04', 'Automate ID verification in account onboarding', 'Manager, Operations', 'Operations', '2025-01-25', '2026-05-28', NULL, 'Overdue', 'Medium');
INSERT INTO public.fact_action VALUES ('A-055', 'R-04', 'Add maker-checker review for new accounts', 'Manager, Operations', 'Operations', '2025-10-07', '2026-02-04', '2026-01-23', 'Closed', 'Medium');
INSERT INTO public.fact_action VALUES ('A-018', 'R-04', 'Retrain branch staff on onboarding procedures', 'Manager, Operations', 'Operations', '2026-04-17', '2026-12-22', NULL, 'In Progress', 'High');
INSERT INTO public.fact_action VALUES ('A-022', 'R-05', 'Document core banking operating procedures', 'COO', 'Operations', '2025-07-02', '2026-11-10', NULL, 'In Progress', 'Medium');
INSERT INTO public.fact_action VALUES ('A-011', 'R-05', 'Cross-train backup staff for core banking roles', 'COO', 'Operations', '2026-01-09', '2026-11-16', NULL, 'In Progress', 'High');
INSERT INTO public.fact_action VALUES ('A-029', 'R-05', 'Build succession plan for key operations roles', 'COO', 'Operations', '2026-02-23', '2026-12-04', NULL, 'In Progress', 'Medium');
INSERT INTO public.fact_action VALUES ('A-026', 'R-07', 'Remediate incomplete member due diligence files', 'Chief Compliance Officer', 'Compliance', '2025-01-02', '2026-08-14', NULL, 'Overdue', 'Low');
INSERT INTO public.fact_action VALUES ('A-049', 'R-07', 'Set review timeframe for high-risk members', 'Chief Compliance Officer', 'Compliance', '2025-06-06', '2026-09-12', NULL, 'Overdue', 'Medium');
INSERT INTO public.fact_action VALUES ('A-021', 'R-07', 'Quality-assure member risk assessments', 'Chief Compliance Officer', 'Compliance', '2026-07-04', '2027-02-02', NULL, 'Open', 'High');
INSERT INTO public.fact_action VALUES ('A-047', 'R-08', 'Assess alternative core banking providers', 'CIO', 'IT', '2025-03-21', '2026-08-02', NULL, 'Overdue', 'Medium');
INSERT INTO public.fact_action VALUES ('A-060', 'R-08', 'Review vendor SOC 2 report and findings', 'CIO', 'IT', '2025-12-01', '2026-03-01', '2026-02-17', 'Closed', 'Medium');
INSERT INTO public.fact_action VALUES ('A-030', 'R-09', 'Complete annual BCP test for critical vendors', 'CIO', 'IT', '2025-05-11', '2026-08-26', NULL, 'Overdue', 'Medium');
INSERT INTO public.fact_action VALUES ('A-003', 'R-09', 'Document exit plan for critical vendors', 'CIO', 'IT', '2025-06-09', '2026-09-28', NULL, 'Overdue', 'High');
INSERT INTO public.fact_action VALUES ('A-008', 'R-09', 'Update third-party risk assessments', 'CIO', 'IT', '2026-03-14', '2027-01-21', NULL, 'In Progress', 'High');
INSERT INTO public.fact_action VALUES ('A-058', 'R-10', 'Complete ransomware tabletop exercise', 'CIO', 'IT', '2025-01-28', '2025-02-27', '2025-02-23', 'Closed', 'Medium');
INSERT INTO public.fact_action VALUES ('A-027', 'R-11', 'Diversify wholesale funding sources', 'CFO', 'Finance', '2025-07-21', '2026-10-17', NULL, 'Open', 'Low');
INSERT INTO public.fact_action VALUES ('A-052', 'R-12', 'Rebalance fixed-rate mortgage hedging', 'CFO', 'Finance', '2025-01-21', '2026-09-08', NULL, 'Overdue', 'High');
INSERT INTO public.fact_action VALUES ('A-009', 'R-12', 'Refresh interest rate sensitivity analysis', 'CFO', 'Finance', '2025-06-02', '2026-10-29', NULL, 'In Progress', 'Medium');
INSERT INTO public.fact_action VALUES ('A-032', 'R-14', 'Complete independent validation of credit models', 'CFO', 'Finance', '2025-01-01', '2026-06-27', NULL, 'Overdue', 'Medium');
INSERT INTO public.fact_action VALUES ('A-020', 'R-14', 'Update model inventory and ownership', 'CFO', 'Finance', '2025-03-13', '2026-07-21', NULL, 'Overdue', 'Low');
INSERT INTO public.fact_action VALUES ('A-042', 'R-14', 'Document model performance monitoring', 'CFO', 'Finance', '2025-05-05', '2026-09-24', NULL, 'Overdue', 'Medium');
INSERT INTO public.fact_action VALUES ('A-053', 'R-06', 'Clear backlog of periodic monitoring reviews', 'Chief Compliance Officer', 'Compliance', '2025-11-02', '2026-11-28', NULL, 'In Progress', 'High');
INSERT INTO public.fact_action VALUES ('A-038', 'R-10', 'Deploy multi-factor authentication to all staff', 'CIO', 'IT', '2025-03-16', '2026-09-04', NULL, 'Overdue', 'High');
INSERT INTO public.fact_action VALUES ('A-016', 'R-13', 'Review member pricing against digital competitors', 'CEO', 'Retail Banking', '2025-09-12', '2026-11-04', NULL, 'Open', 'High');
INSERT INTO public.fact_action VALUES ('A-007', 'R-13', 'Launch digital onboarding improvements', 'CEO', 'Retail Banking', '2025-05-14', '2026-09-16', NULL, 'Overdue', 'High');
INSERT INTO public.fact_action VALUES ('A-025', 'R-07', 'Remediate incomplete member due diligence files - follow-up review', 'Chief Compliance Officer', 'Compliance', '2026-08-14', '2027-02-08', NULL, 'In Progress', 'Low');
INSERT INTO public.fact_action VALUES ('A-005', 'R-09', 'Complete annual BCP test for critical vendors - follow-up review', 'CIO', 'IT', '2026-05-16', '2027-01-09', NULL, 'In Progress', 'High');
INSERT INTO public.fact_action VALUES ('A-054', 'R-09', 'Document exit plan for critical vendors - follow-up review', 'CIO', 'IT', '2026-07-14', '2027-03-04', NULL, 'In Progress', 'Medium');
INSERT INTO public.fact_action VALUES ('A-012', 'R-11', 'Update contingency funding plan - follow-up review', 'CFO', 'Finance', '2025-09-13', '2026-10-05', NULL, 'In Progress', 'Low');
INSERT INTO public.fact_action VALUES ('A-056', 'R-11', 'Run deposit run-off stress scenario - follow-up review', 'CFO', 'Finance', '2026-02-19', '2026-04-20', '2026-03-22', 'Closed', 'High');
INSERT INTO public.fact_action VALUES ('A-014', 'R-14', 'Complete independent validation of credit models - follow-up review', 'CFO', 'Finance', '2025-06-16', '2026-09-20', NULL, 'Overdue', 'High');
INSERT INTO public.fact_action VALUES ('A-051', 'R-14', 'Complete independent validation of credit models - second follow-up', 'CFO', 'Finance', '2026-03-07', '2026-12-16', NULL, 'In Progress', 'Low');
INSERT INTO public.fact_action VALUES ('A-001', 'R-14', 'Update model inventory and ownership - second follow-up', 'CFO', 'Finance', '2026-07-22', '2027-02-20', NULL, 'Open', 'High');
INSERT INTO public.fact_action VALUES ('A-050', 'R-06', 'Clear backlog of periodic monitoring reviews - follow-up review', 'Chief Compliance Officer', 'Compliance', '2026-07-10', '2027-02-26', NULL, 'In Progress', 'High');
INSERT INTO public.fact_action VALUES ('A-048', 'R-06', 'Tune transaction monitoring alert thresholds - follow-up review', 'Chief Compliance Officer', 'Compliance', '2026-07-08', '2027-01-03', NULL, 'In Progress', 'High');
INSERT INTO public.fact_action VALUES ('A-010', 'R-10', 'Test offline backup restoration - follow-up review', 'CIO', 'IT', '2026-07-20', '2027-01-27', NULL, 'In Progress', 'High');
INSERT INTO public.fact_action VALUES ('A-057', 'R-10', 'Deploy multi-factor authentication to all staff - follow-up review', 'CIO', 'IT', '2026-07-01', '2026-12-28', NULL, 'Open', 'High');
INSERT INTO public.fact_action VALUES ('A-041', 'R-13', 'Launch digital onboarding improvements - follow-up review', 'CEO', 'Retail Banking', '2026-06-15', '2027-02-14', NULL, 'In Progress', 'High');


--
-- TOC entry 4976 (class 0 OID 25633)
-- Dependencies: 223
-- Data for Name: fact_incident; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.fact_incident VALUES ('I-001', '2025-12-06', 'Operational', 'Wealth', 'Low', 167.00, 'Closed', 'Documentation gap', '2025-Q4');
INSERT INTO public.fact_incident VALUES ('I-002', '2024-12-10', 'Compliance', 'Lending', 'Medium', 2659.00, 'Closed', 'Training gap', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-003', '2025-03-06', 'Compliance', 'Finance', 'Low', 969.00, 'Open', 'Process gap', '2025-Q1');
INSERT INTO public.fact_incident VALUES ('I-004', '2025-10-13', 'Compliance', 'Wealth', 'Low', 1243.00, 'Closed', 'Training gap', '2025-Q4');
INSERT INTO public.fact_incident VALUES ('I-005', '2024-10-27', 'Third Party', 'Operations', 'High', 74508.00, 'Closed', 'Manual entry error', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-006', '2026-05-30', 'Credit', 'Compliance', 'Medium', 5978.00, 'Closed', 'Training gap', '2026-Q2');
INSERT INTO public.fact_incident VALUES ('I-007', '2024-11-12', 'Credit', 'Operations', 'Low', 877.00, 'Under Review', 'Manual entry error', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-008', '2025-12-05', 'Third Party', 'Operations', 'High', 38736.00, 'Closed', 'Third-party failure', '2025-Q4');
INSERT INTO public.fact_incident VALUES ('I-009', '2025-03-30', 'Credit', 'Compliance', 'Medium', 12657.00, 'Under Review', 'Third-party failure', '2025-Q1');
INSERT INTO public.fact_incident VALUES ('I-010', '2025-12-21', 'Operational', 'Wealth', 'High', 36122.00, 'Under Review', 'System outage', '2025-Q4');
INSERT INTO public.fact_incident VALUES ('I-011', '2026-01-19', 'Third Party', 'Compliance', 'Medium', 8209.00, 'Under Review', 'System outage', '2026-Q1');
INSERT INTO public.fact_incident VALUES ('I-012', '2026-02-12', 'Credit', 'Operations', 'Low', 1633.00, 'Under Review', 'Training gap', '2026-Q1');
INSERT INTO public.fact_incident VALUES ('I-013', '2024-10-11', 'Third Party', 'IT', 'Medium', 3402.00, 'Closed', 'Documentation gap', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-014', '2026-01-31', 'Operational', 'Wealth', 'Medium', 9342.00, 'Closed', 'Third-party failure', '2026-Q1');
INSERT INTO public.fact_incident VALUES ('I-015', '2026-09-09', 'Credit', 'IT', 'Low', 1359.00, 'Under Review', 'Third-party failure', '2026-Q3');
INSERT INTO public.fact_incident VALUES ('I-016', '2026-04-17', 'Technology', 'Lending', 'Low', 1439.00, 'Closed', 'Documentation gap', '2026-Q2');
INSERT INTO public.fact_incident VALUES ('I-017', '2025-04-16', 'Compliance', 'Lending', 'Low', 1521.00, 'Open', 'Third-party failure', '2025-Q2');
INSERT INTO public.fact_incident VALUES ('I-018', '2025-07-11', 'Technology', 'Retail Banking', 'Medium', 14455.00, 'Closed', 'Process gap', '2025-Q3');
INSERT INTO public.fact_incident VALUES ('I-019', '2025-05-21', 'Compliance', 'Wealth', 'Low', 619.00, 'Closed', 'Manual entry error', '2025-Q2');
INSERT INTO public.fact_incident VALUES ('I-020', '2026-04-20', 'Operational', 'Compliance', 'Low', 1933.00, 'Closed', 'Training gap', '2026-Q2');
INSERT INTO public.fact_incident VALUES ('I-021', '2025-07-19', 'Technology', 'Compliance', 'Medium', 7582.00, 'Under Review', 'Manual entry error', '2025-Q3');
INSERT INTO public.fact_incident VALUES ('I-022', '2024-12-06', 'Compliance', 'Lending', 'Low', 151.00, 'Open', 'Process gap', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-023', '2024-12-27', 'Credit', 'IT', 'Critical', 184097.00, 'Open', 'System outage', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-024', '2026-03-20', 'Third Party', 'Wealth', 'Low', 1860.00, 'Open', 'Training gap', '2026-Q1');
INSERT INTO public.fact_incident VALUES ('I-025', '2024-12-01', 'Compliance', 'Wealth', 'Medium', 3625.00, 'Open', 'Manual entry error', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-026', '2025-03-10', 'Third Party', 'Finance', 'Low', 1130.00, 'Open', 'Training gap', '2025-Q1');
INSERT INTO public.fact_incident VALUES ('I-027', '2026-01-25', 'Third Party', 'Retail Banking', 'Low', 474.00, 'Open', 'System outage', '2026-Q1');
INSERT INTO public.fact_incident VALUES ('I-028', '2025-06-28', 'Third Party', 'Retail Banking', 'Medium', 11663.00, 'Open', 'System outage', '2025-Q2');
INSERT INTO public.fact_incident VALUES ('I-029', '2026-07-26', 'Compliance', 'Compliance', 'Low', 544.00, 'Under Review', 'Training gap', '2026-Q3');
INSERT INTO public.fact_incident VALUES ('I-030', '2026-05-06', 'Third Party', 'Wealth', 'High', 45716.00, 'Open', 'Training gap', '2026-Q2');
INSERT INTO public.fact_incident VALUES ('I-031', '2026-02-18', 'Technology', 'IT', 'Low', 1224.00, 'Under Review', 'Manual entry error', '2026-Q1');
INSERT INTO public.fact_incident VALUES ('I-032', '2025-01-02', 'Technology', 'IT', 'Low', 1380.00, 'Closed', 'System outage', '2025-Q1');
INSERT INTO public.fact_incident VALUES ('I-033', '2026-01-25', 'Third Party', 'Operations', 'Medium', 6557.00, 'Under Review', 'Manual entry error', '2026-Q1');
INSERT INTO public.fact_incident VALUES ('I-034', '2026-01-25', 'Compliance', 'Wealth', 'Low', 682.00, 'Under Review', 'Documentation gap', '2026-Q1');
INSERT INTO public.fact_incident VALUES ('I-035', '2026-02-20', 'Operational', 'Finance', 'Low', 1935.00, 'Closed', 'Process gap', '2026-Q1');
INSERT INTO public.fact_incident VALUES ('I-036', '2025-06-16', 'Operational', 'Operations', 'Low', 1986.00, 'Open', 'Third-party failure', '2025-Q2');
INSERT INTO public.fact_incident VALUES ('I-037', '2025-11-28', 'Third Party', 'Compliance', 'Low', 1061.00, 'Closed', 'System outage', '2025-Q4');
INSERT INTO public.fact_incident VALUES ('I-038', '2025-07-01', 'Operational', 'Retail Banking', 'Medium', 6719.00, 'Open', 'Training gap', '2025-Q3');
INSERT INTO public.fact_incident VALUES ('I-039', '2025-06-03', 'Third Party', 'Retail Banking', 'Medium', 11024.00, 'Closed', 'Manual entry error', '2025-Q2');
INSERT INTO public.fact_incident VALUES ('I-040', '2026-01-16', 'Credit', 'Operations', 'High', 47661.00, 'Under Review', 'Third-party failure', '2026-Q1');
INSERT INTO public.fact_incident VALUES ('I-041', '2026-02-07', 'Third Party', 'Lending', 'Critical', 112917.00, 'Open', 'Training gap', '2026-Q1');
INSERT INTO public.fact_incident VALUES ('I-042', '2025-02-17', 'Technology', 'Compliance', 'High', 66773.00, 'Open', 'Process gap', '2025-Q1');
INSERT INTO public.fact_incident VALUES ('I-043', '2024-10-03', 'Third Party', 'Compliance', 'Low', 611.00, 'Closed', 'Third-party failure', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-044', '2026-04-05', 'Third Party', 'Finance', 'Medium', 11042.00, 'Under Review', 'System outage', '2026-Q2');
INSERT INTO public.fact_incident VALUES ('I-045', '2026-09-15', 'Operational', 'Wealth', 'Low', 784.00, 'Open', 'Third-party failure', '2026-Q3');
INSERT INTO public.fact_incident VALUES ('I-046', '2026-09-23', 'Compliance', 'Finance', 'High', 58495.00, 'Closed', 'System outage', '2026-Q3');
INSERT INTO public.fact_incident VALUES ('I-047', '2026-02-27', 'Operational', 'IT', 'Critical', 190423.00, 'Under Review', 'Manual entry error', '2026-Q1');
INSERT INTO public.fact_incident VALUES ('I-048', '2025-02-25', 'Technology', 'Wealth', 'Low', 1340.00, 'Open', 'Documentation gap', '2025-Q1');
INSERT INTO public.fact_incident VALUES ('I-049', '2025-11-12', 'Third Party', 'Wealth', 'Medium', 7383.00, 'Open', 'Documentation gap', '2025-Q4');
INSERT INTO public.fact_incident VALUES ('I-050', '2026-02-12', 'Technology', 'Lending', 'High', 19484.00, 'Open', 'Manual entry error', '2026-Q1');
INSERT INTO public.fact_incident VALUES ('I-051', '2025-12-19', 'Third Party', 'Lending', 'Critical', 101347.00, 'Open', 'Process gap', '2025-Q4');
INSERT INTO public.fact_incident VALUES ('I-052', '2024-10-30', 'Technology', 'Finance', 'Low', 1630.00, 'Closed', 'System outage', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-053', '2026-03-28', 'Compliance', 'Retail Banking', 'Low', 1396.00, 'Open', 'Third-party failure', '2026-Q1');
INSERT INTO public.fact_incident VALUES ('I-054', '2026-06-27', 'Third Party', 'Operations', 'Medium', 11554.00, 'Under Review', 'Third-party failure', '2026-Q2');
INSERT INTO public.fact_incident VALUES ('I-055', '2025-06-19', 'Credit', 'Lending', 'Medium', 9622.00, 'Closed', 'Third-party failure', '2025-Q2');
INSERT INTO public.fact_incident VALUES ('I-056', '2025-09-19', 'Third Party', 'Compliance', 'Critical', 140561.00, 'Under Review', 'System outage', '2025-Q3');
INSERT INTO public.fact_incident VALUES ('I-057', '2025-10-29', 'Technology', 'IT', 'High', 39993.00, 'Under Review', 'Documentation gap', '2025-Q4');
INSERT INTO public.fact_incident VALUES ('I-058', '2025-07-30', 'Operational', 'IT', 'Low', 1699.00, 'Open', 'Documentation gap', '2025-Q3');
INSERT INTO public.fact_incident VALUES ('I-059', '2024-11-20', 'Compliance', 'IT', 'High', 69580.00, 'Under Review', 'System outage', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-060', '2026-07-14', 'Compliance', 'Operations', 'Low', 513.00, 'Closed', 'Documentation gap', '2026-Q3');
INSERT INTO public.fact_incident VALUES ('I-061', '2026-07-24', 'Technology', 'Operations', 'Low', 1615.00, 'Closed', 'Manual entry error', '2026-Q3');
INSERT INTO public.fact_incident VALUES ('I-062', '2025-07-30', 'Credit', 'Wealth', 'Low', 850.00, 'Open', 'Training gap', '2025-Q3');
INSERT INTO public.fact_incident VALUES ('I-063', '2025-07-07', 'Technology', 'Compliance', 'High', 67854.00, 'Closed', 'Third-party failure', '2025-Q3');
INSERT INTO public.fact_incident VALUES ('I-064', '2024-12-17', 'Credit', 'Wealth', 'Low', 1979.00, 'Closed', 'Third-party failure', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-065', '2024-10-15', 'Credit', 'Finance', 'Low', 253.00, 'Open', 'Process gap', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-066', '2025-01-19', 'Technology', 'IT', 'Medium', 2410.00, 'Closed', 'Documentation gap', '2025-Q1');
INSERT INTO public.fact_incident VALUES ('I-067', '2024-12-04', 'Third Party', 'Retail Banking', 'Medium', 13486.00, 'Closed', 'Manual entry error', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-068', '2024-11-08', 'Credit', 'Lending', 'Low', 1008.00, 'Under Review', 'Third-party failure', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-069', '2025-10-15', 'Credit', 'Operations', 'Medium', 13411.00, 'Open', 'System outage', '2025-Q4');
INSERT INTO public.fact_incident VALUES ('I-070', '2025-11-29', 'Technology', 'Retail Banking', 'Medium', 10017.00, 'Open', 'Process gap', '2025-Q4');
INSERT INTO public.fact_incident VALUES ('I-071', '2025-05-11', 'Operational', 'Operations', 'Low', 1946.00, 'Under Review', 'Training gap', '2025-Q2');
INSERT INTO public.fact_incident VALUES ('I-072', '2026-07-23', 'Third Party', 'Retail Banking', 'Low', 815.00, 'Open', 'System outage', '2026-Q3');
INSERT INTO public.fact_incident VALUES ('I-073', '2026-07-20', 'Compliance', 'Lending', 'Medium', 2349.00, 'Open', 'System outage', '2026-Q3');
INSERT INTO public.fact_incident VALUES ('I-074', '2024-12-10', 'Compliance', 'Wealth', 'High', 53429.00, 'Closed', 'Training gap', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-075', '2024-10-03', 'Compliance', 'Retail Banking', 'Low', 296.00, 'Open', 'Manual entry error', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-076', '2025-02-12', 'Technology', 'Retail Banking', 'Low', 1617.00, 'Closed', 'Process gap', '2025-Q1');
INSERT INTO public.fact_incident VALUES ('I-077', '2024-11-23', 'Third Party', 'Finance', 'Low', 862.00, 'Under Review', 'Training gap', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-078', '2026-05-31', 'Credit', 'Wealth', 'Low', 1031.00, 'Under Review', 'Documentation gap', '2026-Q2');
INSERT INTO public.fact_incident VALUES ('I-079', '2024-11-01', 'Third Party', 'Operations', 'Low', 980.00, 'Under Review', 'Manual entry error', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-080', '2024-12-22', 'Credit', 'Operations', 'Low', 303.00, 'Open', 'Training gap', '2024-Q4');
INSERT INTO public.fact_incident VALUES ('I-081', '2025-08-29', 'Credit', 'IT', 'Low', 1223.00, 'Under Review', 'Manual entry error', '2025-Q3');
INSERT INTO public.fact_incident VALUES ('I-082', '2026-09-19', 'Compliance', 'Finance', 'Low', 1340.00, 'Under Review', 'System outage', '2026-Q3');
INSERT INTO public.fact_incident VALUES ('I-083', '2025-11-28', 'Technology', 'Finance', 'Low', 928.00, 'Under Review', 'Documentation gap', '2025-Q4');
INSERT INTO public.fact_incident VALUES ('I-084', '2025-06-19', 'Operational', 'Compliance', 'Low', 312.00, 'Closed', 'Manual entry error', '2025-Q2');
INSERT INTO public.fact_incident VALUES ('I-085', '2025-12-17', 'Credit', 'Retail Banking', 'Low', 1513.00, 'Open', 'Training gap', '2025-Q4');
INSERT INTO public.fact_incident VALUES ('I-086', '2026-04-29', 'Third Party', 'Compliance', 'Low', 250.00, 'Open', 'Manual entry error', '2026-Q2');
INSERT INTO public.fact_incident VALUES ('I-087', '2025-07-22', 'Compliance', 'Lending', 'Medium', 3697.00, 'Open', 'Third-party failure', '2025-Q3');
INSERT INTO public.fact_incident VALUES ('I-088', '2025-05-18', 'Technology', 'IT', 'High', 39088.00, 'Closed', 'Third-party failure', '2025-Q2');
INSERT INTO public.fact_incident VALUES ('I-089', '2026-04-28', 'Credit', 'Retail Banking', 'Critical', 243479.00, 'Open', 'Documentation gap', '2026-Q2');
INSERT INTO public.fact_incident VALUES ('I-090', '2026-09-11', 'Technology', 'Wealth', 'Low', 369.00, 'Closed', 'System outage', '2026-Q3');


--
-- TOC entry 4974 (class 0 OID 25608)
-- Dependencies: 221
-- Data for Name: fact_kri_value; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.fact_kri_value VALUES ('K-01', '2024-Q4', 90.62);
INSERT INTO public.fact_kri_value VALUES ('K-01', '2025-Q1', 94.27);
INSERT INTO public.fact_kri_value VALUES ('K-01', '2025-Q2', 99.58);
INSERT INTO public.fact_kri_value VALUES ('K-01', '2025-Q4', 92.69);
INSERT INTO public.fact_kri_value VALUES ('K-01', '2026-Q1', 75.63);
INSERT INTO public.fact_kri_value VALUES ('K-01', '2026-Q2', 84.56);
INSERT INTO public.fact_kri_value VALUES ('K-01', '2026-Q3', 91.46);
INSERT INTO public.fact_kri_value VALUES ('K-02', '2024-Q4', 88.93);
INSERT INTO public.fact_kri_value VALUES ('K-02', '2025-Q1', 84.22);
INSERT INTO public.fact_kri_value VALUES ('K-02', '2025-Q2', 83.00);
INSERT INTO public.fact_kri_value VALUES ('K-02', '2025-Q3', 87.83);
INSERT INTO public.fact_kri_value VALUES ('K-02', '2025-Q4', 72.56);
INSERT INTO public.fact_kri_value VALUES ('K-02', '2026-Q1', 63.78);
INSERT INTO public.fact_kri_value VALUES ('K-02', '2026-Q2', 71.05);
INSERT INTO public.fact_kri_value VALUES ('K-02', '2026-Q3', 78.84);
INSERT INTO public.fact_kri_value VALUES ('K-03', '2024-Q4', 1.74);
INSERT INTO public.fact_kri_value VALUES ('K-03', '2025-Q1', 1.84);
INSERT INTO public.fact_kri_value VALUES ('K-03', '2025-Q2', 1.85);
INSERT INTO public.fact_kri_value VALUES ('K-03', '2025-Q3', 1.90);
INSERT INTO public.fact_kri_value VALUES ('K-03', '2025-Q4', 1.82);
INSERT INTO public.fact_kri_value VALUES ('K-03', '2026-Q1', 1.78);
INSERT INTO public.fact_kri_value VALUES ('K-03', '2026-Q2', 1.88);
INSERT INTO public.fact_kri_value VALUES ('K-03', '2026-Q3', 1.90);
INSERT INTO public.fact_kri_value VALUES ('K-04', '2024-Q4', 1.11);
INSERT INTO public.fact_kri_value VALUES ('K-04', '2025-Q1', 1.14);
INSERT INTO public.fact_kri_value VALUES ('K-04', '2025-Q2', 1.08);
INSERT INTO public.fact_kri_value VALUES ('K-04', '2025-Q3', 1.09);
INSERT INTO public.fact_kri_value VALUES ('K-04', '2025-Q4', 1.09);
INSERT INTO public.fact_kri_value VALUES ('K-04', '2026-Q1', 1.14);
INSERT INTO public.fact_kri_value VALUES ('K-04', '2026-Q2', 1.09);
INSERT INTO public.fact_kri_value VALUES ('K-04', '2026-Q3', 1.15);
INSERT INTO public.fact_kri_value VALUES ('K-06', '2024-Q4', 81.92);
INSERT INTO public.fact_kri_value VALUES ('K-06', '2025-Q1', 83.09);
INSERT INTO public.fact_kri_value VALUES ('K-06', '2025-Q2', 82.28);
INSERT INTO public.fact_kri_value VALUES ('K-06', '2025-Q3', 83.11);
INSERT INTO public.fact_kri_value VALUES ('K-06', '2025-Q4', 83.34);
INSERT INTO public.fact_kri_value VALUES ('K-06', '2026-Q1', 87.69);
INSERT INTO public.fact_kri_value VALUES ('K-06', '2026-Q2', 84.58);
INSERT INTO public.fact_kri_value VALUES ('K-06', '2026-Q3', 86.77);
INSERT INTO public.fact_kri_value VALUES ('K-09', '2024-Q4', 84.16);
INSERT INTO public.fact_kri_value VALUES ('K-09', '2025-Q1', 80.70);
INSERT INTO public.fact_kri_value VALUES ('K-09', '2025-Q2', 83.93);
INSERT INTO public.fact_kri_value VALUES ('K-09', '2025-Q3', 85.98);
INSERT INTO public.fact_kri_value VALUES ('K-09', '2025-Q4', 87.13);
INSERT INTO public.fact_kri_value VALUES ('K-09', '2026-Q1', 92.22);
INSERT INTO public.fact_kri_value VALUES ('K-09', '2026-Q2', 93.92);
INSERT INTO public.fact_kri_value VALUES ('K-09', '2026-Q3', 88.37);
INSERT INTO public.fact_kri_value VALUES ('K-01', '2025-Q3', 99.20);
INSERT INTO public.fact_kri_value VALUES ('K-05', '2024-Q4', 8.00);
INSERT INTO public.fact_kri_value VALUES ('K-05', '2025-Q1', 8.00);
INSERT INTO public.fact_kri_value VALUES ('K-05', '2025-Q2', 8.00);
INSERT INTO public.fact_kri_value VALUES ('K-05', '2025-Q3', 8.00);
INSERT INTO public.fact_kri_value VALUES ('K-05', '2025-Q4', 8.00);
INSERT INTO public.fact_kri_value VALUES ('K-05', '2026-Q1', 8.00);
INSERT INTO public.fact_kri_value VALUES ('K-05', '2026-Q2', 8.00);
INSERT INTO public.fact_kri_value VALUES ('K-05', '2026-Q3', 8.00);
INSERT INTO public.fact_kri_value VALUES ('K-08', '2024-Q4', 6.00);
INSERT INTO public.fact_kri_value VALUES ('K-08', '2025-Q1', 6.00);
INSERT INTO public.fact_kri_value VALUES ('K-08', '2025-Q2', 6.00);
INSERT INTO public.fact_kri_value VALUES ('K-08', '2025-Q3', 6.00);
INSERT INTO public.fact_kri_value VALUES ('K-08', '2025-Q4', 6.00);
INSERT INTO public.fact_kri_value VALUES ('K-08', '2026-Q1', 6.00);
INSERT INTO public.fact_kri_value VALUES ('K-08', '2026-Q2', 6.00);
INSERT INTO public.fact_kri_value VALUES ('K-08', '2026-Q3', 6.00);
INSERT INTO public.fact_kri_value VALUES ('K-07', '2024-Q4', 119.61);
INSERT INTO public.fact_kri_value VALUES ('K-07', '2025-Q1', 118.30);
INSERT INTO public.fact_kri_value VALUES ('K-07', '2025-Q2', 120.43);
INSERT INTO public.fact_kri_value VALUES ('K-07', '2025-Q3', 117.90);
INSERT INTO public.fact_kri_value VALUES ('K-07', '2025-Q4', 115.63);
INSERT INTO public.fact_kri_value VALUES ('K-07', '2026-Q1', 118.67);
INSERT INTO public.fact_kri_value VALUES ('K-07', '2026-Q2', 113.35);
INSERT INTO public.fact_kri_value VALUES ('K-07', '2026-Q3', 112.86);


--
-- TOC entry 4972 (class 0 OID 25588)
-- Dependencies: 219
-- Data for Name: fact_risk_rating; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.fact_risk_rating VALUES ('R-01', '2024-Q4', '2024-12-31', 3, 4, 'Effective', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-01', '2025-Q1', '2025-03-31', 3, 4, 'Effective', 2, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-01', '2025-Q2', '2025-06-30', 3, 4, 'Effective', 2, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-01', '2025-Q3', '2025-09-30', 3, 4, 'Effective', 2, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-01', '2025-Q4', '2025-12-31', 3, 4, 'Effective', 2, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-01', '2026-Q1', '2026-03-31', 3, 4, 'Effective', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-01', '2026-Q2', '2026-06-30', 3, 4, 'Effective', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-01', '2026-Q3', '2026-09-30', 3, 4, 'Effective', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-02', '2024-Q4', '2024-12-31', 3, 4, 'Effective', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-02', '2025-Q1', '2025-03-31', 3, 4, 'Effective', 2, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-02', '2025-Q2', '2025-06-30', 3, 4, 'Effective', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-02', '2025-Q3', '2025-09-30', 3, 4, 'Effective', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-02', '2025-Q4', '2025-12-31', 3, 4, 'Effective', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-02', '2026-Q1', '2026-03-31', 3, 4, 'Effective', 2, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-02', '2026-Q2', '2026-06-30', 3, 4, 'Effective', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-02', '2026-Q3', '2026-09-30', 3, 4, 'Effective', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-03', '2024-Q4', '2024-12-31', 3, 3, 'Effective', 1, 2);
INSERT INTO public.fact_risk_rating VALUES ('R-03', '2025-Q1', '2025-03-31', 3, 3, 'Effective', 1, 2);
INSERT INTO public.fact_risk_rating VALUES ('R-03', '2025-Q2', '2025-06-30', 3, 3, 'Effective', 1, 2);
INSERT INTO public.fact_risk_rating VALUES ('R-03', '2025-Q3', '2025-09-30', 3, 3, 'Effective', 1, 2);
INSERT INTO public.fact_risk_rating VALUES ('R-03', '2025-Q4', '2025-12-31', 3, 3, 'Effective', 1, 2);
INSERT INTO public.fact_risk_rating VALUES ('R-03', '2026-Q1', '2026-03-31', 3, 3, 'Effective', 1, 2);
INSERT INTO public.fact_risk_rating VALUES ('R-03', '2026-Q2', '2026-06-30', 3, 3, 'Effective', 2, 2);
INSERT INTO public.fact_risk_rating VALUES ('R-03', '2026-Q3', '2026-09-30', 3, 3, 'Effective', 1, 2);
INSERT INTO public.fact_risk_rating VALUES ('R-04', '2024-Q4', '2024-12-31', 4, 3, 'Needs Improvement', 3, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-04', '2025-Q1', '2025-03-31', 4, 3, 'Needs Improvement', 3, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-04', '2025-Q2', '2025-06-30', 4, 3, 'Needs Improvement', 2, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-04', '2025-Q3', '2025-09-30', 4, 3, 'Needs Improvement', 3, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-04', '2025-Q4', '2025-12-31', 4, 3, 'Needs Improvement', 3, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-04', '2026-Q1', '2026-03-31', 4, 3, 'Needs Improvement', 3, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-04', '2026-Q2', '2026-06-30', 4, 3, 'Needs Improvement', 3, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-04', '2026-Q3', '2026-09-30', 4, 3, 'Needs Improvement', 3, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-05', '2024-Q4', '2024-12-31', 3, 4, 'Needs Improvement', 2, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-05', '2025-Q1', '2025-03-31', 3, 4, 'Needs Improvement', 2, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-05', '2025-Q2', '2025-06-30', 3, 4, 'Needs Improvement', 1, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-05', '2025-Q3', '2025-09-30', 3, 4, 'Needs Improvement', 2, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-05', '2025-Q4', '2025-12-31', 3, 4, 'Needs Improvement', 2, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-05', '2026-Q1', '2026-03-31', 3, 4, 'Needs Improvement', 2, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-05', '2026-Q2', '2026-06-30', 3, 4, 'Needs Improvement', 2, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-05', '2026-Q3', '2026-09-30', 3, 4, 'Needs Improvement', 2, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-06', '2024-Q4', '2024-12-31', 4, 5, 'Needs Improvement', 3, 5);
INSERT INTO public.fact_risk_rating VALUES ('R-06', '2025-Q1', '2025-03-31', 4, 5, 'Needs Improvement', 3, 5);
INSERT INTO public.fact_risk_rating VALUES ('R-06', '2025-Q2', '2025-06-30', 4, 5, 'Needs Improvement', 3, 5);
INSERT INTO public.fact_risk_rating VALUES ('R-06', '2025-Q3', '2025-09-30', 4, 5, 'Needs Improvement', 3, 5);
INSERT INTO public.fact_risk_rating VALUES ('R-06', '2025-Q4', '2025-12-31', 4, 5, 'Needs Improvement', 3, 5);
INSERT INTO public.fact_risk_rating VALUES ('R-06', '2026-Q1', '2026-03-31', 4, 5, 'Needs Improvement', 3, 5);
INSERT INTO public.fact_risk_rating VALUES ('R-06', '2026-Q2', '2026-06-30', 4, 5, 'Effective', 2, 5);
INSERT INTO public.fact_risk_rating VALUES ('R-06', '2026-Q3', '2026-09-30', 4, 5, 'Effective', 2, 5);
INSERT INTO public.fact_risk_rating VALUES ('R-07', '2024-Q4', '2024-12-31', 4, 4, 'Needs Improvement', 3, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-07', '2025-Q1', '2025-03-31', 4, 4, 'Needs Improvement', 3, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-07', '2025-Q2', '2025-06-30', 4, 4, 'Needs Improvement', 3, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-07', '2025-Q3', '2025-09-30', 4, 4, 'Needs Improvement', 3, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-07', '2025-Q4', '2025-12-31', 4, 4, 'Needs Improvement', 3, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-07', '2026-Q1', '2026-03-31', 4, 4, 'Needs Improvement', 3, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-07', '2026-Q2', '2026-06-30', 4, 4, 'Effective', 2, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-07', '2026-Q3', '2026-09-30', 4, 4, 'Effective', 2, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-08', '2024-Q4', '2024-12-31', 3, 5, 'Effective', 1, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-08', '2025-Q1', '2025-03-31', 3, 5, 'Effective', 1, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-08', '2025-Q2', '2025-06-30', 3, 5, 'Effective', 2, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-08', '2025-Q3', '2025-09-30', 3, 5, 'Effective', 1, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-08', '2025-Q4', '2025-12-31', 3, 5, 'Effective', 1, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-08', '2026-Q1', '2026-03-31', 3, 5, 'Effective', 1, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-08', '2026-Q2', '2026-06-30', 3, 5, 'Effective', 1, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-08', '2026-Q3', '2026-09-30', 3, 5, 'Effective', 1, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-09', '2024-Q4', '2024-12-31', 3, 4, 'Needs Improvement', 2, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-09', '2025-Q1', '2025-03-31', 3, 4, 'Needs Improvement', 2, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-09', '2025-Q2', '2025-06-30', 3, 4, 'Needs Improvement', 2, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-09', '2025-Q3', '2025-09-30', 3, 4, 'Needs Improvement', 2, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-09', '2025-Q4', '2025-12-31', 3, 4, 'Needs Improvement', 2, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-09', '2026-Q1', '2026-03-31', 3, 4, 'Needs Improvement', 2, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-09', '2026-Q2', '2026-06-30', 3, 4, 'Needs Improvement', 2, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-09', '2026-Q3', '2026-09-30', 3, 4, 'Needs Improvement', 2, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-10', '2024-Q4', '2024-12-31', 4, 5, 'Needs Improvement', 3, 5);
INSERT INTO public.fact_risk_rating VALUES ('R-10', '2025-Q1', '2025-03-31', 4, 5, 'Needs Improvement', 3, 5);
INSERT INTO public.fact_risk_rating VALUES ('R-10', '2025-Q2', '2025-06-30', 4, 5, 'Needs Improvement', 3, 5);
INSERT INTO public.fact_risk_rating VALUES ('R-10', '2025-Q3', '2025-09-30', 4, 5, 'Needs Improvement', 3, 5);
INSERT INTO public.fact_risk_rating VALUES ('R-10', '2025-Q4', '2025-12-31', 4, 5, 'Needs Improvement', 3, 5);
INSERT INTO public.fact_risk_rating VALUES ('R-10', '2026-Q1', '2026-03-31', 4, 5, 'Needs Improvement', 3, 5);
INSERT INTO public.fact_risk_rating VALUES ('R-10', '2026-Q2', '2026-06-30', 4, 5, 'Needs Improvement', 3, 5);
INSERT INTO public.fact_risk_rating VALUES ('R-10', '2026-Q3', '2026-09-30', 4, 5, 'Needs Improvement', 3, 5);
INSERT INTO public.fact_risk_rating VALUES ('R-11', '2024-Q4', '2024-12-31', 2, 5, 'Effective', 1, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-11', '2025-Q1', '2025-03-31', 2, 5, 'Effective', 1, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-11', '2025-Q2', '2025-06-30', 2, 5, 'Effective', 1, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-11', '2025-Q3', '2025-09-30', 2, 5, 'Effective', 1, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-11', '2025-Q4', '2025-12-31', 2, 5, 'Effective', 1, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-11', '2026-Q1', '2026-03-31', 2, 5, 'Effective', 1, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-11', '2026-Q2', '2026-06-30', 2, 5, 'Effective', 1, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-11', '2026-Q3', '2026-09-30', 2, 5, 'Effective', 1, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-12', '2024-Q4', '2024-12-31', 3, 4, 'Effective', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-12', '2025-Q1', '2025-03-31', 3, 4, 'Effective', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-12', '2025-Q2', '2025-06-30', 3, 4, 'Effective', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-12', '2025-Q3', '2025-09-30', 3, 4, 'Effective', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-12', '2025-Q4', '2025-12-31', 3, 4, 'Effective', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-12', '2026-Q1', '2026-03-31', 3, 4, 'Effective', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-12', '2026-Q2', '2026-06-30', 3, 4, 'Effective', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-12', '2026-Q3', '2026-09-30', 3, 4, 'Effective', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-13', '2024-Q4', '2024-12-31', 4, 4, 'Needs Improvement', 3, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-13', '2025-Q1', '2025-03-31', 4, 4, 'Needs Improvement', 3, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-13', '2025-Q2', '2025-06-30', 4, 4, 'Needs Improvement', 3, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-13', '2025-Q3', '2025-09-30', 4, 4, 'Needs Improvement', 3, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-13', '2025-Q4', '2025-12-31', 4, 4, 'Needs Improvement', 3, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-13', '2026-Q1', '2026-03-31', 4, 4, 'Needs Improvement', 3, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-13', '2026-Q2', '2026-06-30', 4, 4, 'Needs Improvement', 3, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-13', '2026-Q3', '2026-09-30', 4, 4, 'Needs Improvement', 3, 4);
INSERT INTO public.fact_risk_rating VALUES ('R-14', '2024-Q4', '2024-12-31', 3, 3, 'Needs Improvement', 2, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-14', '2025-Q1', '2025-03-31', 3, 3, 'Needs Improvement', 1, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-14', '2025-Q2', '2025-06-30', 3, 3, 'Needs Improvement', 2, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-14', '2025-Q3', '2025-09-30', 3, 3, 'Needs Improvement', 2, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-14', '2025-Q4', '2025-12-31', 3, 3, 'Needs Improvement', 2, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-14', '2026-Q1', '2026-03-31', 3, 3, 'Needs Improvement', 2, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-14', '2026-Q2', '2026-06-30', 3, 3, 'Needs Improvement', 2, 3);
INSERT INTO public.fact_risk_rating VALUES ('R-14', '2026-Q3', '2026-09-30', 3, 3, 'Needs Improvement', 2, 3);


--
-- TOC entry 4977 (class 0 OID 25664)
-- Dependencies: 228
-- Data for Name: report_config; Type: TABLE DATA; Schema: public; Owner: -
--

INSERT INTO public.report_config VALUES (true, '2026-09-30', 12);


--
-- TOC entry 4803 (class 2606 OID 25607)
-- Name: dim_kri dim_kri_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dim_kri
    ADD CONSTRAINT dim_kri_pkey PRIMARY KEY (kri_id);


--
-- TOC entry 4797 (class 2606 OID 25582)
-- Name: dim_quarter dim_quarter_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dim_quarter
    ADD CONSTRAINT dim_quarter_pkey PRIMARY KEY (quarter);


--
-- TOC entry 4799 (class 2606 OID 25587)
-- Name: dim_risk dim_risk_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dim_risk
    ADD CONSTRAINT dim_risk_pkey PRIMARY KEY (risk_id);


--
-- TOC entry 4813 (class 2606 OID 33861)
-- Name: dim_user_access dim_user_access_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.dim_user_access
    ADD CONSTRAINT dim_user_access_pkey PRIMARY KEY (user_email, business_unit);


--
-- TOC entry 4807 (class 2606 OID 25627)
-- Name: fact_action fact_action_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_action
    ADD CONSTRAINT fact_action_pkey PRIMARY KEY (action_id);


--
-- TOC entry 4809 (class 2606 OID 25637)
-- Name: fact_incident fact_incident_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_incident
    ADD CONSTRAINT fact_incident_pkey PRIMARY KEY (incident_id);


--
-- TOC entry 4805 (class 2606 OID 25612)
-- Name: fact_kri_value fact_kri_value_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_kri_value
    ADD CONSTRAINT fact_kri_value_pkey PRIMARY KEY (kri_id, quarter);


--
-- TOC entry 4801 (class 2606 OID 25592)
-- Name: fact_risk_rating fact_risk_rating_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_risk_rating
    ADD CONSTRAINT fact_risk_rating_pkey PRIMARY KEY (risk_id, quarter);


--
-- TOC entry 4811 (class 2606 OID 25670)
-- Name: report_config report_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_config
    ADD CONSTRAINT report_config_pkey PRIMARY KEY (id);


--
-- TOC entry 4818 (class 2606 OID 25628)
-- Name: fact_action fact_action_risk_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_action
    ADD CONSTRAINT fact_action_risk_id_fkey FOREIGN KEY (risk_id) REFERENCES public.dim_risk(risk_id);


--
-- TOC entry 4816 (class 2606 OID 25613)
-- Name: fact_kri_value fact_kri_value_kri_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_kri_value
    ADD CONSTRAINT fact_kri_value_kri_id_fkey FOREIGN KEY (kri_id) REFERENCES public.dim_kri(kri_id);


--
-- TOC entry 4817 (class 2606 OID 25618)
-- Name: fact_kri_value fact_kri_value_quarter_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_kri_value
    ADD CONSTRAINT fact_kri_value_quarter_fkey FOREIGN KEY (quarter) REFERENCES public.dim_quarter(quarter);


--
-- TOC entry 4814 (class 2606 OID 25598)
-- Name: fact_risk_rating fact_risk_rating_quarter_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_risk_rating
    ADD CONSTRAINT fact_risk_rating_quarter_fkey FOREIGN KEY (quarter) REFERENCES public.dim_quarter(quarter);


--
-- TOC entry 4815 (class 2606 OID 25593)
-- Name: fact_risk_rating fact_risk_rating_risk_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_risk_rating
    ADD CONSTRAINT fact_risk_rating_risk_id_fkey FOREIGN KEY (risk_id) REFERENCES public.dim_risk(risk_id);


--
-- TOC entry 4819 (class 2606 OID 25672)
-- Name: fact_incident fk_incident_quarter; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.fact_incident
    ADD CONSTRAINT fk_incident_quarter FOREIGN KEY (quarter) REFERENCES public.dim_quarter(quarter);


-- Completed on 2026-10-12 22:21:11

--
-- PostgreSQL database dump complete
--

