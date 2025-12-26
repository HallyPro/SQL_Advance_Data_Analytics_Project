-- Change Over TIme Analysis
SELECT 
    YEAR(order_date) AS order_year,
    SUM(sales_amount) AS total_sales,
    COUNT(DISTINCT customer_key) AS total_customers,
    SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY YEAR(order_date)
ORDER BY YEAR(order_date)


-- Cumulative Analysis
-->> Calculate the total sales per month and the running total of Sales over time
SELECT
    order_date,
    Total_sales,
    SUM(Total_sales) OVER (ORDER BY order_date) AS running_total_sales
FROM (
        SELECT
            DATETRUNC(month, order_date) AS order_date,
            SUM(sales_amount) AS Total_sales
        FROM gold.fact_sales
        WHERE order_date IS NOT NULL
        GROUP BY DATETRUNC(month, order_date)
)t


-- Performance Analysis
/* Analyze the yearly performance of products by comparing their sales to both 
the average sales performance of the product and the previous year's sales */
WITH yearly_product_sales AS (
    SELECT 
        YEAR(f.order_date) AS order_year,
        p.product_name AS product_name,
        SUM(f.sales_amount) AS current_sales
    FROM gold.fact_sales f 
    LEFT JOIN gold.dim_products p 
    ON f.product_key = p.product_key
    WHERE f.order_date IS NOT NULL
    GROUP BY YEAR(f.order_date),
                p.product_name
)

SELECT 
    order_year,
    product_name,
    current_sales,
    AVG(current_Sales) OVER(PARTITION BY product_name) AS avg_sales,
    current_sales - AVG(current_Sales) OVER(PARTITION BY product_name) AS sales_per,
    CASE 
        WHEN current_sales - AVG(current_Sales) OVER(PARTITION BY product_name) > 0 THEN 'Above Avg'
        WHEN current_sales - AVG(current_Sales) OVER(PARTITION BY product_name) < 0 THEN 'Below Avg'
        ELSE 'Avg'
    END AS per_stat,
    LAG(current_Sales) OVER(PARTITION BY product_name ORDER BY order_year) AS prev_yr_sales,
    current_sales - LAG(current_Sales) OVER(PARTITION BY product_name ORDER BY order_year) AS YoY,
    CASE 
        WHEN current_sales - LAG(current_Sales) OVER(PARTITION BY product_name ORDER BY order_year) > 0 THEN 'Increased'
        WHEN current_sales - LAG(current_Sales) OVER(PARTITION BY product_name ORDER BY order_year) < 0 THEN 'Decreased'
        ELSE 'No Change'
    END AS YoY_stat
FROM yearly_product_sales;


-- Part-To-Whole Analysis
    -->> Which Categories contribute the most to overall sales?
WITH category_sales AS (
    SELECT 
        category,
        SUM(sales_amount) total_sales
    FROM gold.fact_sales f 
    LEFT JOIN gold.dim_products p 
    ON f.product_key = p.product_key
    GROUP BY category
)

SELECT
    category,
    total_sales,
    SUM(total_sales) OVER() AS overall_sales,
    CONCAT(ROUND((CAST (total_sales AS FLOAT)/SUM(total_sales) OVER()) * 100, 2), '%') AS Percentage_of_total
FROM category_sales
ORDER BY total_sales DESC


-- Data Segmentation
    /* Segment products into cost ranges and count how many products
        falls into each segment */
WITH product_segments AS (
    SELECT
        product_key,
        product_name,
        cost,
        CASE
            WHEN cost < 100 THEN 'Below 100'
            WHEN cost BETWEEN 100 AND 500 THEN '100-500'
            WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
            ELSE 'Above 1000'
        END cost_range
    FROM gold.dim_products
)

SELECT 
    cost_range,
    COUNT(product_key) AS total_products
FROM product_segments
GROUP BY cost_range
ORDER BY total_products DESC

/* Group customers into three segments based on their spending behavior:
        - Vip: at least 12 months of history and spending more than $5000
        - Regular: at least 12 months of history spending $5000 or less
        - New: lifespan less than 12 months.
And find the total number of customers per each group. */
WITH customer_spending AS (
    SELECT
        c.customer_key,
        SUM(f.sales_amount) AS total_spending,
        MIN(order_date) AS first_order,
        MAX(order_date) AS last_order,
        DATEDIFF(month,  MIN(order_date),  MAX(order_date)) AS lifespan
    FROM gold.fact_sales f 
    LEFT JOIN gold.dim_customers c 
    ON f.customer_key = c.customer_key
    GROUP BY c.customer_key
)

SELECT
    customer_segment,
    COUNT(customer_key) AS total_customers
FROM(
    SELECT
        customer_key,
        CASE
            WHEN lifespan >= 12 AND total_spending > 5000 THEN 'VIP'
            WHEN lifespan >= 12 AND total_spending <= 5000 THEN 'Regular'
            ELSE 'New'
        END customer_segment
    FROM customer_spending
)t
GROUP BY customer_segment
ORDER BY total_customers DESC