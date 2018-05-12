USE MDMTLA

-- clean up if a previous script failed to clean up
 IF OBJECT_ID('tempdb.dbo.#results', 'U') IS NOT NULL
 DROP TABLE #results;

 IF OBJECT_ID('tempdb.dbo.#finalresults', 'U') IS NOT NULL
 DROP TABLE #finalresults;

 IF OBJECT_ID('tempdb.dbo.#allowables', 'U') IS NOT NULL
 DROP TABLE #allowables;

 IF OBJECT_ID('tempdb.dbo.#allowableloading', 'U') IS NOT NULL
 DROP TABLE #allowableloading;

-- Define the variables we need to collect data
-- List of keys we need to re-use
DECLARE @TransformerID BIGINT
DECLARE @TransformerIDentifier VARCHAR(50) = 'OH63572837010'
DECLARE @TransformerName VARCHAR(50)
DECLARE @LocationNumber VARCHAR(50)
DECLARE @SubstationName VARCHAR(50)
DECLARE @FeederName VARCHAR(50)

-- Calculated or aggregate variables needed for the table
DECLARE @PhaseCount INT
DECLARE @kVAmin DECIMAL(18,8)
DECLARE @kVAmax DECIMAL(18,8)
DECLARE @kVAavg DECIMAL(18,8)
DECLARE @kVAmaxDate DATETIME
DECLARE @DateMin DATETIME
DECLARE @DateMax DATETIME
DECLARE @kVAsum DECIMAL(18,8)
DECLARE @kVARating  DECIMAL(18,8)
DECLARE @EquivalentContinuousPriorLoad  DECIMAL(18,8)
DECLARE @EquivalentContinuousPriorLoadIntervalCount INT
DECLARE @EquivalentContinuousPostLoad  DECIMAL(18,8)
DECLARE @EquivalentContinuousPostLoadIntervalCount INT
DECLARE @EquivalentContinuousMaxLoad  DECIMAL(18,8)
DECLARE @AmbientTemperatureF  DECIMAL(18,8)
DECLARE @AmbientTemperatureC  DECIMAL(18,8)
DECLARE @TemperatureBelowThirtyMultiplier  DECIMAL(18,8)
DECLARE @TemperatureAboveThirtyMultiplier  DECIMAL(18,8)
DECLARE @DateMaxLoadDuration DATETIME
DECLARE @DateMinLoadDuration DATETIME
DECLARE @LoadDurationHours INT
DECLARE @AllowableLoadingPercentageColumn VARCHAR(50)
DECLARE @AllowableLoadingPercentage DECIMAL(18,8)
DECLARE @ActualLoadingPercentage DECIMAL(18,8)
DECLARE @TransformerRatingPredictedChoice VARCHAR(50)
DECLARE @TransformerRatingPredictedLoadingPercentage DECIMAL(18,8)
DECLARE @CreatedDate DATETIME = GETDATE()

-- matrix of allowable 
DECLARE @AllowableLoading TABLE 
    ( 
        DurationHrs int,
        Fifty DECIMAL(18,4),
        SeventyFive DECIMAL(18,4),
        Ninety DECIMAL(18,4),
        DiffToNextValue INT
    )

INSERT  INTO @AllowableLoading (DurationHrs, Fifty, SeventyFive, Ninety, DiffToNextValue)
SELECT  1, 2.12,1.96,1.82,1
INSERT  INTO @AllowableLoading (DurationHrs, Fifty, SeventyFive, Ninety, DiffToNextValue)
SELECT  2, 1.79,1.68,1.57,2
INSERT  INTO @AllowableLoading (DurationHrs, Fifty, SeventyFive, Ninety, DiffToNextValue)
SELECT  4, 1.50,1.44,1.36,2
INSERT  INTO @AllowableLoading (DurationHrs, Fifty, SeventyFive, Ninety, DiffToNextValue)
SELECT  6, 1.34,1.31,1.26,2
INSERT  INTO @AllowableLoading (DurationHrs, Fifty, SeventyFive, Ninety, DiffToNextValue) 
SELECT  8, 1.28,1.25,1.21,4
INSERT  INTO @AllowableLoading (DurationHrs, Fifty, SeventyFive, Ninety, DiffToNextValue)
SELECT  12, 1.22,1.19,1.17,4
INSERT  INTO @AllowableLoading (DurationHrs, Fifty, SeventyFive, Ninety, DiffToNextValue)
SELECT  16, 1.17,1.15,1.13,4
INSERT  INTO @AllowableLoading (DurationHrs, Fifty, SeventyFive, Ninety, DiffToNextValue)
SELECT  20, 1.13,1.11,1.10,4
INSERT  INTO @AllowableLoading (DurationHrs, Fifty, SeventyFive, Ninety, DiffToNextValue)
SELECT  24, 1.08,1.07,1.07,4


-- Why 12 hours, what's the reasoning?  Smallest sample size?
-- IEEE PDF... 
-- Do I store this as well?
DECLARE @timeIntervalHours INT = 12

-- Find the max kVA for one transfomer
-- DECLARE @kVAmedian  DECIMAL(18,4) to hard use some data sci frameworks
-- DECLARE @kVAmode  DECIMAL(18,4) to hard use some data sci frameworks
-- Do this properly...  min, max, avg (mean), median etc..  sd
-- What do we do when kVAmax is 0 (zero)????????????
-- We need to add in a note and flag to inspect the entire record
-- the data we have where zero's exist have zero's over the entire date range of data
-- so the min, max, avg should be an indicate something is wrong...
SELECT
        @kVAmin  = min(d.kVAReadValue),
        @kVAmax  = max(d.kVAReadValue),
        @kVAavg  = avg(d.kVAReadValue),
        @DateMin = min(ReadDate),
        @DateMax = max(ReadDate),
        @kVAsum  = sum(d.kVAReadValue)
FROM
TLAReadHeader h
INNER JOIN TLAReadDetail d
    ON d.TLAReadHeaderId = h.TLAReadHeaderID
WHERE h.TransformerIDentifier = @TransformerIDentifier

-- Get the ReadDate of the max peak of the lastest readings.
-- We can have the peak with the same value for multiple timestamps
-- When this occurs we will sort the data desc, and get the max readdate
SELECT TOP 1 @kVAmaxDate = d.ReadDate, @AmbientTemperatureF = Temperature
FROM
    TLAReadHeader h
INNER JOIN TLAReadDetail d
        ON d.TLAReadHeaderId = h.TLAReadHeaderID
    WHERE d.kVAReadValue = (
        SELECT max(d.kVAReadValue)
            FROM
            TLAReadHeader h
            INNER JOIN TLAReadDetail d
                ON d.TLAReadHeaderId = h.TLAReadHeaderID
            WHERE h.TransformerIDentifier = @TransformerIDentifier)
        AND h.TransformerIDentifier = @TransformerIDentifier
ORDER BY d.ReadDate DESC

-- For predicting the future load a transformer can carry at some future time in unknown ambient
-- you use the average daily temperature for the month involved, average over several years
-- you can also use the average of the maximum daily temperatures for the month involved averaged over serveral years
-- Temperature in F for the max kW read, where do we get this?
-- Code for temperature ... to adjust allowable load matrix
-- If the load duration spans more than 1 hour this should be the average temperature right???????
-- Instead of the temperature at the peak
SET @AmbientTemperatureC = (@AmbientTemperatureF - 32) * 5/9
SET @TemperatureBelowThirtyMultiplier = (30 - @AmbientTemperatureC) 
SET @TemperatureAboveThirtyMultiplier = (@AmbientTemperatureC - 30)

-- Set negative values to zero for the equation
IF (@TemperatureBelowThirtyMultiplier < 0)
BEGIN
    SET @TemperatureBelowThirtyMultiplier = 0
END
IF (@TemperatureAboveThirtyMultiplier < 0)
BEGIN
    SET @TemperatureAboveThirtyMultiplier = 0
END

SELECT 
		DurationHrs,
        Fifty = (Fifty*100 + ((-1.5* @TemperatureAboveThirtyMultiplier) + (1 * @TemperatureBelowThirtyMultiplier))),
        SeventyFive= (SeventyFive*100 + ((-1.5* @TemperatureAboveThirtyMultiplier) + (1 * @TemperatureBelowThirtyMultiplier))),
        Ninety= (Ninety*100 + ((-1.5* @TemperatureAboveThirtyMultiplier) + (1 * @TemperatureBelowThirtyMultiplier))),
		DiffToNextValue
INTO #allowableloading
FROM @AllowableLoading

-- Initial Query to review what kind of data we have
-- Get the 12 hours before the start of the first peak over the kVA Rating
-- Get the 12 hours after the end of the KVARating drops off (12 + (# of Hours over kVA - 1)
-- Might have to re-work this to requery the data again since we need the count for Over Rating
-- We can have dupe data so we need to remove or just take the latest TLAReadHeaderId
SELECT 
          h.TLAReadHeaderID 
        , h.TransformerIDentifier
        , d.ReadDate
        , KVARating
        , CASE 
            WHEN d.kVAReadValue >= h.KVARating
                THEN 1 
            ELSE 0
        END AS OverRating
    INTO #results
FROM
    TLAReadHeader h
INNER JOIN TLAReadDetail d
        ON d.TLAReadHeaderId = h.TLAReadHeaderID
    WHERE h.TransformerIDentifier = @TransformerIDentifier
    AND d.ReadDate BETWEEN DATEADD(HOUR,-@timeIntervalHours,@kVAmaxDate) AND DATEADD(HOUR,@timeIntervalHours,@kVAmaxDate)
    ORDER BY d.ReadDate

-- how to get the 12 hours from the bump, hump the lenght of the peak load ... on the left and right sides
-- this will only work if we have a hump, which means undersized transformers needs a different way to be reviewed
-- detecting the slope for each point and the change of slope might work here
SELECT @kVARating = max(KVARating) 
FROM #results
        WHERE TransformerIDentifier = @TransformerIDentifier
 
SELECT @DateMinLoadDuration = MIN(ReadDate) FROM #results where overrating = 1
SELECT @DateMaxLoadDuration = MAX(ReadDate) FROM #results where overrating = 1 

IF(@DateMinLoadDuration IS NULL)
BEGIN
    SELECT @DateMinLoadDuration = MAX(ReadDate) FROM #results where ReadDate < @kVAmaxDate
END
IF(@DateMaxLoadDuration IS NULL)
BEGIN
    SELECT @DateMaxLoadDuration = MIN(ReadDate) FROM #results where ReadDate > @kVAmaxDate
END
--SELECT @DateMinLoadDuration, @DateMaxLoadDuration, DATEADD(HOUR,-@timeIntervalHours,@DateMinLoadDuration), DATEADD(HOUR,@timeIntervalHours,@DateMaxLoadDuration)

SELECT 
          d.ReadDate
        , d.kVAReadValue
        , d.kWValue
        , h.KVARating
        , SQUARE(d.kVAReadValue) kVaSqaured
        , CASE 
            WHEN d.kVAReadValue >= h.KVARating
                THEN 1 
            ELSE 0
        END AS OverRating
        ,h.ReadLogDate
    INTO #finalresults
    FROM
    TLAReadHeader h
    INNER JOIN TLAReadDetail d
        ON d.TLAReadHeaderId = h.TLAReadHeaderID
    WHERE h.TransformerIDentifier = @TransformerIDentifier
    AND d.ReadDate BETWEEN DATEADD(HOUR,-@timeIntervalHours,@DateMinLoadDuration) AND DATEADD(HOUR,@timeIntervalHours,@DateMaxLoadDuration)
    GROUP BY       
         d.ReadDate, d.kVAReadValue, d.kWValue, h.KVARating, SQUARE(d.kVAReadValue) ,
    CASE 
            WHEN d.kVAReadValue >= h.KVARating
                THEN 1 
            ELSE 0
    END
    , h.ReadLogDate
    ORDER BY d.ReadDate

-- this is in-efficient
-- another way is to query MDM.dbo.Transformer, but this crosses databases and is even worse
SELECT DISTINCT 
	     @TransformerID = TransformerID
        ,@TransformerIDentifier = TransformerIDentifier
        ,@TransformerName = TransformerName
        ,@LocationNumber = LocationNumber
        ,@SubstationName = SubstationName
        ,@FeederName = FeederName 
FROM MDMTLA.dbo.TLAReadHeader
WHERE TransformerIDentifier = @TransformerIDentifier

--What do we want to do if the kVAmax is zero.
--Check if all the intervals are zero??? Alert someone
IF (@kVAmax = 0)
BEGIN
    PRINT(@TransformerName + ' has @kVAmax: ' + @kVAmax + ', @kVAsum: ' + @kVAsum)
END

PRINT('HERE')


-- Get the number of hours where were over the kVARating
-- removed OverRating=1 because what if one interval in the middle is not over rated
-- the load duration is still a duration we just had one outlier
-- another idea is what if we have bi-model duration in AM and duration in PM
-- how do we represent this in the data pull...
SET @LoadDurationHours = (SELECT COUNT(ReadDate) FROM #finalresults where ReadDate BETWEEN @DateMinLoadDuration AND @DateMaxLoadDuration)

-- if we get zero for @LoadDurationHours, it might mean none of the values where over the kVA rating
-- so we just a peak value of one hour for right now
-- what about datediff instead of count(*) ....
IF (@LoadDurationHours = 0 )
BEGIN
    SET @LoadDurationHours = 1 --(SELECT COUNT(*) FROM #finalresults WHERE  ReadDate BETWEEN @DateMinLoadDuration AND @DateMaxLoadDuration)
END

-- Data Needed for final results
-- Actual Load Percentage
SET @ActualLoadingPercentage = (@kVAmax / @KVARating)*100
--SELECT 'ActualLoadingPercentage', @ActualLoadingPercentage

-- Root Mean Square to calculate the loading over 12 hours, what happens if we don't have 12 hours?????
-- IEEE pdf which references RMS
-- https://en.wikipedia.org/wiki/Root_mean_square
-- Equivalent Pre Loading Calculation
-- Equivalent Post Loading Calculation
SELECT @EquivalentContinuousPriorLoad = SUM(kVaSqaured)/COUNT(ReadDate) 
FROM #finalresults
 WHERE ReadDate < @DateMinLoadDuration

 SELECT @EquivalentContinuousPriorLoadIntervalCount = COUNT(ReadDate)
 FROM #finalresults
 WHERE ReadDate < @DateMinLoadDuration

 SELECT @EquivalentContinuousPriorLoad = SQRT(@EquivalentContinuousPriorLoad)

 SELECT @EquivalentContinuousPostLoad= SUM(kVaSqaured)/COUNT(ReadDate) FROM #finalresults
 WHERE ReadDate > @DateMaxLoadDuration

 SELECT @EquivalentContinuousPostLoadIntervalCount = COUNT(ReadDate) FROM #finalresults
 WHERE ReadDate > @DateMaxLoadDuration

 SELECT @EquivalentContinuousPostLoad = SQRT(@EquivalentContinuousPostLoad)

 SELECT @EquivalentContinuousMaxLoad =  MAX(val) FROM (SELECT @EquivalentContinuousPriorLoad AS val UNION ALL SELECT @EquivalentContinuousPostLoad AS val) tbl

 SELECT @EquivalentContinuousMaxLoad = (@EquivalentContinuousMaxLoad / MAX(KVARating))*100 FROM #finalresults

 -- Choose the Allowable Loading Percentage Column based on calculation results
 DECLARE @columnName VARCHAR(20)
 IF (@EquivalentContinuousMaxLoad <= 50)
 BEGIN
     SET @columnName = 'Fifty'
 END
 IF (@EquivalentContinuousMaxLoad > 50 AND @EquivalentContinuousMaxLoad <= 75)
 BEGIN
     SET @columnName = 'SeventyFive'
 END
 IF (@EquivalentContinuousMaxLoad > 75)
 BEGIN
     SET @columnName= 'Ninety'
 END

 --SELECT 'PreConditionLoadingMax', @EquivalentContinuousMaxLoad, @columnName
 SELECT @AllowableLoadingPercentageColumn = @columnName

 -- Attempt to do it all in one query
 SELECT
   DurationHrs
 , @columnName ActualLoadPercentageColumn
 , CASE 
     WHEN @columnName = 'Fifty' THEN Fifty
     WHEN @columnName = 'SeventyFive' THEN SeventyFive
     WHEN @columnName = 'Ninety' THEN Ninety 
 END AS AllowableLoadingPercentage
 , @LoadDurationHours LoadDurationInHours
 INTO #allowables
 FROM #allowableloading
 WHERE @LoadDurationHours >= DurationHrs AND @LoadDurationHours < (DurationHrs + DiffToNextValue)

SELECT 
    @AllowableLoadingPercentage = AllowableLoadingPercentage
FROM #allowables


-- Alpha - Untested
SELECT @PhaseCount = 
PhaseCount FROM MDM.dbo.Transformer
WHERE TransformerIdentifier = @TransformerIDentifier

-- Focus on over loaded transformers right now
-- 
IF (@AllowableLoadingPercentage < @ActualLoadingPercentage)
BEGIN
    SELECT TOP 1
         @TransformerRatingPredictedChoice = kVARating
        ,@TransformerRatingPredictedLoadingPercentage =  ( @KVAmax / KVARating ) * 100
    FROM MDMTLA.dbo.TLAInventory
    WHERE PhaseCount = @PhaseCount
    AND kVARating > @KVARating
    AND ( @KVAmax / KVARating ) * 100 < @AllowableLoadingPercentage
    ORDER BY kVARating ASC

    SELECT * FROM #allowables
END

IF (@AllowableLoadingPercentage > @ActualLoadingPercentage)
BEGIN
    SELECT TOP 1
         @TransformerRatingPredictedChoice = kVARating
        ,@TransformerRatingPredictedLoadingPercentage =  ( @KVAmax / KVARating ) * 100
    FROM MDMTLA.dbo.TLAInventory
    WHERE PhaseCount = @PhaseCount
    AND kVARating <= @KVARating
    AND ( @KVAmax / KVARating ) * 100 < @AllowableLoadingPercentage
    ORDER BY kVARating ASC
END

 IF OBJECT_ID('tempdb.dbo.#results', 'U') IS NOT NULL
 DROP TABLE #results;

 IF OBJECT_ID('tempdb.dbo.#finalresults', 'U') IS NOT NULL
 DROP TABLE #finalresults;

 IF OBJECT_ID('tempdb.dbo.#allowables', 'U') IS NOT NULL
 DROP TABLE #allowables;

 IF OBJECT_ID('tempdb.dbo.#allowableloading', 'U') IS NOT NULL
 DROP TABLE #allowableloading;

-- Remove old data - note if insert fails we have lost data
--DELETE FROM MDMTLA.dbo.TLALoadingAnalysis
--WHERE TransformerIDentifier = @TransformerIDentifier

-- Add the updated max and calculation results
--INSERT INTO MDMTLA.dbo.TLALoadingAnalysis
SELECT 
     @TransformerID TransformerID
    ,@TransformerIDentifier TransformerIDentifier
    ,@TransformerName TransformerName
    ,@LocationNumber LocationNumber
    ,@SubstationName SubstationName
    ,@FeederName FeederName
    ,@kVAmin kVAmin
    ,@kVAmax kVAmax
    ,@kVAavg kVAavg
    ,@kVAmaxDate kVAmaxDate
    ,@DateMin DateMin
    ,@DateMax DateMax
    ,@kVARating kVARating
    ,@EquivalentContinuousPriorLoad EquivalentContinuousPriorLoad
    ,@EquivalentContinuousPriorLoadIntervalCount EquivalentContinuousPriorLoadIntervalCount
    ,@EquivalentContinuousPostLoad EquivalentContinuousPostLoad
    ,@EquivalentContinuousPostLoadIntervalCount EquivalentContinuousPostLoadIntervalCount
    ,@EquivalentContinuousMaxLoad EquivalentContinuousMaxLoad
    ,@AmbientTemperatureF AmbientTemperatureF
    ,@AmbientTemperatureC AmbientTemperatureC
    ,@TemperatureBelowThirtyMultiplier TemperatureBelowThirtyMultiplier
    ,@TemperatureAboveThirtyMultiplier TemperatureAboveThirtyMultiplier
    ,@DateMaxLoadDuration DateMaxLoadDuration
    ,@DateMinLoadDuration DateMinLoadDuration
    ,@LoadDurationHours LoadDurationHours
    ,@AllowableLoadingPercentageColumn AllowableLoadingPercentageColumn
    ,@AllowableLoadingPercentage AllowableLoadingPercentage
    ,@ActualLoadingPercentage ActualLoadingPercentage
    ,@TransformerRatingPredictedChoice TransformerRatingUpSized
    ,@TransformerRatingPredictedLoadingPercentage TransformerRatingPredictedLoadingPercentage
    ,@CreatedDate CreateDate

    --SELECT * FROM TLALoadingAnalysis
    --WHERE TransformerIDentifier = @TransformerIDentifier