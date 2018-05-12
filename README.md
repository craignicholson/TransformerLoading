# Transformer Loading Process and Analysis

The goal of this application is to find transformers which are overloaded and
recommend the appropriate sized transformer.

## Requirements

- kW ,Power Factor, abd/or kVA per hour (Intervals for one hour is the only supported data interval)
- MDM.dbo.Transformer.PhaseCount: Tranformer Phases to determine correct sized transformer.
- MDMTLA.dbo.TLAInventory: List of Transformer Sizes by Phase for the Utility (stocked in warehouse)
- Temperarture in F

## Calculating Overloaded Transformer

### Steps

Adhoc List for Analysis

- Create the Allowable Loading Matrix with default values
- Set the interval prior and post fitler to 12 hours
- Pull a list of Transformers from the MDM or MDMTLA.dbo.TLAHeader table
- Collect the min, max, average, sum for kVA
- Collect the min, max for ReadDate (This lets us log the fitler or date range)
- Collect the date of the kVAmax and the ambient temperature of that hour. Note, we will take the latest hour if the kVAmax occurs more than once.
- Convert the temperature from F to C
- Calculate the temperature multipliers for the Allowable Loading Matrix
- Calculate the Root Mean Square (RMS) for the prior and post load

Additional Notes

- For predicting the future load a transformer can carry at some future time in unknown ambient
- You use the average daily temperature for the month involved, average over several years
- You can also use the average of the maximum daily temperatures for the month involved averaged over serveral years
- Temperature in F for the max kW read, where do we get this?
- Code for temperature ... to adjust allowable load matrix
- If the load duration spans more than 1 hour this should be the average temperature right???????
- Instead of the temperature at the peak

Adjustments for Chart:
-1.5% for each degree above 30°C
+1.0% for each degree below 30°C

Valid for altitudes up to 3000 meters
Above 3000 meters
-.4% for every 100m above 3000m for ONAN
-0.5% for every 100m above 3000m for ONAF

Example Code Block - Not Production Ready

```sql
    SET @AmbientAvgTemperatureC = (@AmbientAvgTemperatureF - 32) * 5/9
    SET @TemperatureBelowThirtyMultiplier = (30 - @AmbientAvgTemperatureC)
    SET @TemperatureAboveThirtyMultiplier = (@AmbientAvgTemperatureC - 30)

    -- Set negative values to zero for the equation
    IF (@TemperatureBelowThirtyMultiplier < 0)
    BEGIN
        SET @TemperatureBelowThirtyMultiplier = 0
    END
    IF (@TemperatureAboveThirtyMultiplier < 0)
    BEGIN
        SET @TemperatureAboveThirtyMultiplier = 0
    END

    -- multiply by 100 to show the percentage value
    UPDATE @AllowableLoading
        SET
        Fifty = (Fifty*100 + ((-1.5* @TemperatureAboveThirtyMultiplier) + (1 * @TemperatureBelowThirtyMultiplier))),
        SeventyFive= (SeventyFive*100 + ((-1.5* @TemperatureAboveThirtyMultiplier) + (1 * @TemperatureBelowThirtyMultiplier))),
        Ninety= (Ninety*100 + ((-1.5* @TemperatureAboveThirtyMultiplier) + (1 * @TemperatureBelowThirtyMultiplier)))
```

Find the Load Duration for the kVAmax

- Mark all values as over or under the kVARating
- Check to see if these values are near the kVAmax
- Collect the Read Date min and max for values where kVA is greating than the kVARating
- These values may contain irregular results is the first hour of the day (Hour 0) is over the kVARating, but the Load Duration occurs during the middle of the day.
- We can clean these bad values up later in the process

Collect the kVA data for the min and max Load Duration, the hour which are the start and end of the load duration

- Start creating the data needed to calculate the Root Mean Square (RMS) for the Equivalent Load to compare to the Actual Load
- Add new column to square the kVA, we will use kVA in the RMS.
- Weed out duplicate values - Note this first pass only groups the data up instead of choosing the latest header id - Need to revisit the de-dupe process

Calculate the Load Duration

- Load Duration will be the start of the load and the end of the load with a peak in the middle
- Note, this has issues which need to be reviewed ... so we can see if Tranformer like OH65567491004 affect the results

Calculate the  ActualLoadingPercentage

- @kVAmax / @KVARating)*100

Calculate the RMS for the EquivalentContinuousPriorLoad and EquivalentContinuousPostLoad

- EquivalentContinuousPriorLoad will be the 12 hours before the load duration starts, or at least an attempt to collect what hours we have available before the load duration.
- EquivalentContinuousPostLoad will be the 12 hours after the load duration ends, or at least an attempt to collect what hours we have available after the load duration.
- We should develop a limit which allows us to drop out of the calculation when we are missing too much data

Additional Notes

- Root Mean Square to calculate the loading over 12 hours, what happens if we don't have 12 hours?
- IEEE pdf which references RMS
- https://en.wikipedia.org/wiki/Root_mean_square
- Equivalent Pre Loading Calculation
- Equivalent Post Loading Calculation

Example

 ```sql

    SELECT @EquivalentContinuousPriorLoad = SUM(kVaSqaured)/COUNT(*) 
    FROM #finalresults
    WHERE ReadDate < @DateMinLoadDuration

    SELECT @EquivalentContinuousPriorLoadIntervalCount = COUNT(*)
    FROM #finalresults
    WHERE ReadDate < @DateMinLoadDuration

    -- Should this be a columns too???
    SELECT @EquivalentContinuousPriorLoad = SQRT(@EquivalentContinuousPriorLoad)

    SELECT @EquivalentContinuousPostLoad= SUM(kVaSqaured)/COUNT(*) FROM #finalresults
    WHERE ReadDate > @DateMaxLoadDuration

    SELECT @EquivalentContinuousPostLoadIntervalCount = COUNT(*) FROM #finalresults
    WHERE ReadDate > @DateMaxLoadDuration

    --Should this me a column too?
    SELECT @EquivalentContinuousPostLoad = SQRT(@EquivalentContinuousPostLoad)

```

- Pick the max value from EquivalentContinuousPriorLoad and EquivalentContinuousPostLoad
- The max value will be used to choose the column value from the Allowable Loading Matrix

```sql

   SELECT @EquivalentContinuousMaxLoad =  MAX(val)
   FROM
    (SELECT @EquivalentContinuousPriorLoad AS val
     UNION ALL SELECT @EquivalentContinuousPostLoad AS val
    ) tbl

   SELECT @EquivalentContinuousMaxLoad = (@EquivalentContinuousMaxLoad / MAX(KVARating)) * 100
   FROM #finalresults

 ```

### Example of the Allowable Loading Matrix

**Example Table @ 30 C values*

| DurationHrs | Fifty    |  SeventyFive | Ninety  | DiffToNextValue|
|-------------|----------|--------------|---------|---------------:|
| 1           | 212.0 | 196.0    | 182.0 | 1              |
| 2           | 179.0 | 168.0    | 157.0 | 2              |
| 4           | 150.0 | 144.0    | 136.0 | 2              |
| 6           | 134.0 | 131.0    | 126.0 | 2              |
| 8           | 128.0 | 125.0    | 121.0 | 4              |
| 12          | 122.0 | 119.0    | 117.0 | 4              |
| 16          | 117.0 | 115.0    | 113.0 | 4              |
| 20          | 113.0 | 111.0    | 110.0 | 4              |
| 24          | 108.0 | 107.0    | 107.0 | 4              |

Why are 75 and 90 % both 107 for hour 24?  Glitch in the matrix?

Set by the IEEE Document

- Duration In Hours
- 50% Loading
- 75% Loading
- 90% Loading

Difference to next value is used to help choose the correct bucket to choose when comparing the ActualLoadingPercentage to AllowableLoadingPercentage.

When EquivalentContinuousMaxLoad <= 50, then 50
When EquivalentContinuousMaxLoad > 50 AND EquivalentContinuousMaxLoad <= 75 , then 75
When EquivalentContinuousMaxLoad > 75 then 90

- Compare the ActualLoadingPercentage and the AllowableLoadingPercentage in the matrix
 -- Use the Load Duration in Hours to choose the y value
 -- Use the EquivalentContinuousMaxLoad to choose the x column
 -- The AllowableLoadingPercentage is the value defined.

When ActualLoadingPercentage is greater than AllowableLoadingPercentage, the transformer is overloaded.

## Resizing the Transformer

Steps

- Need to know the phases single, two, three phase for the transformer
- Need to know what the current tranformer kVARating is
- Need to know what transformers and phases the utiltity has in stock
- Once we detect the transformer is undersized just re-use the values to pick a transformer

Example List of Transformers and Predicted Loading

- Variables
 -- kVAmax = 164.366
 -- kVA Rating - current is 112
 -- AllowableLoadingPrecentage for the peak and temp is 131.39 %

Results Table Example
kVa Transformer, Predicted Loading

112, (kVAmax / 150 ) * 100  = 145.95% is higher than the AllowableLoadingPrecentage,
...
150, (kVAmax / 150 ) * 100  = 109.58%, is lower than the AllowableLoadingPercentage
225, (kVAmax / 150 ) * 100  = 73.05%, is lower than the AllowableLoadingPercentage
...

## TLALoadingAnalysis Results Table

**This table is alpha stage and columns might be added and removed*

- Stores one record for each transformer.
- Data is removed with each analysis run and updated.
- History is not kept, since data might be incorrect and need to be re-calculated on each import.
- Process will run after each TransformerLoadingAnalysisEngine Runs to import and flag events.

```sql
USE MDMTLA
DROP TABLE [dbo].[TLALoadingAnalysis]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[TLALoadingAnalysis](
    [TransformerID] [bigint] NOT NULL,
    [TransformerIDentifier] [varchar](50) NULL,
    [TransformerName] [varchar](50) NULL,
    [LocationNumber] [varchar](50),
    [SubstationName] [varchar](50),
    [FeederName] [varchar](50),
    [kVAmin] [decimal](18,6) NULL,
    [kVAmax] [decimal](18,8) NULL,
    [kVASum] [decimal](18,8) NULL,
    [kVAavg] [decimal](18,8) NULL,
    [kVAmaxDate] [datetime] NULL,
    [DateMin] [datetime]  NULL,
    [DateMax] [datetime] NULL,
    [kVARating] [decimal](18,8) NULL,
    [PhaseCount] INT NULL,
    [EquivalentContinuousPriorLoad] [decimal](18,8) NULL,
    [EquivalentContinuousPriorLoadIntervalCount]  INT NULL,
    [EquivalentContinuousPostLoad] [decimal](18,8) NULL,
    [EquivalentContinuousPostLoadIntervalCount] INT NULL,
    [EquivalentContinuousMaxLoad] [decimal](18,8) NULL,
    [AmbientTemperatureF] [decimal](18,8) NULL,
    [AmbientTemperatureC] [decimal](18,8) NULL,
    [TemperatureBelowThirtyMultiplier] [decimal](18,8) NULL,
    [TemperatureAboveThirtyMultiplier] [decimal](18,8) NULL,
    [DateMaxLoadDuration] [datetime] NULL,
    [DateMinLoadDuration] [datetime] NULL,
    [LoadDurationHours] [INT] NULL,
    [AllowableLoadingPercentageColumn] [varchar](50),
    [AllowableLoadingPercentage] [decimal](18,8),
    [ActualLoadingPercentage] [decimal](18,8),
    [TransformerRatingPredictedChoice] [decimal](18,8) NULL,
    [TransformerRatingPredictedLoadingPercentage] [decimal](18,8) NULL,
    [CreatedDate] [datetime]
) ON [PRIMARY]
GO
CREATE UNIQUE INDEX IX_TransformerIDentifier
    ON TLALoadingAnalysis (TransformerIDentifier);

```

### Quering TLALoadingAnalysis

Filter on TranformerIDentifier, there will be one record per TransformerIDentifier.  

If for the data in the TLAReadHeader table has duplicate TransfomerIDentifier(s) for more than one TransfomerId
the last TransformerIDentifier we iterate over will be saved.

### Column Descriptions

#### TransformerID

Primary key from MDM.dbo.Transformer table, right?  MDMTLA has not data dictionary which describes this field.  Or is this from the MDMVMD database?

#### TransformerIDentifier

Identifier from MDM.dbo.Transformer.TransformerIdentifier typically similar to a LocationName or Key identifier in another database. Or is this from the MDMVMD database????

#### TransformerName

Name from MDM.dbo.Transformer table...??????????

#### LocationNumber

The location number which relates back to a map point, see MDM.dbo.Locations

#### SubstationName

The name of the substation which is upstread of the transformer, see MDM.dbo.Substation.

#### FeederName

The name of the Feeder which is upstream of the transformer.

#### kVAmin

The minimum kVAReadValue for the analysis range.

#### kVAmax

The maximum kVAReadValue for the analysis range.

### kVAsum

The total kVA summed up. This value can be used to help determine when we have kVAsum of zero that
all the values we have collected are also zeros, indicating an issue with the data.

#### kVAavg

The average or mean kVAReadValue for the analysis range.

Average can be mis-leading and SQL Server really needs a way to calculate the median value. What we try and observe is the mean and the median are close in value.  When mean and median differ we know the data is skewed, having lots of small values on some very few large values.

#### kVAmaxDate

The max date for the max kVAReadValue for the analysis range.
The Read Date the kVA max value occured on, sort by most recent at the top.  So this read date will bethe most recent date if the max value occurs more than once in the dataset

During testing we discovered kVA max values of zeros.

#### DateMin

Minimum date for the analyis range.

#### DateMax

Maximum date for the analyis range.

Storing the min and max date range allows the user to see the timeframe this
data has been in service.  The range could be days or years which affects the results.  The longer the time frame
the better the analysis will be since we have more opportunities over the years to see a true max peak, rather
than date existing just during the spring.

#### kVARating

KVA Rating for the Transformer, which is dependant on the number of phases a transformer supports.

#### PhaseCount

Represents the number of phases a tranformer supports.  Typically a transformer will support
single, two, and three phases represented with an interger (1,2,3).  When determining the correct transfomer
we need to determine the number of phases currently supported.

If no match can be made this value can be NULL.

#### EquivalentPeakLoad (NOT USED)

Equivalent peak load for the usual load cycle is the rms load obtained by Equation(5) for the limited period over which the major part of the actual irregular peak seems to exist. The estimated duration of the peak has considerableinfluence over the rms peak value. If the duration is over-estimated, the rms peak value may be considerably below the maximum peak demand. To guard against overheating due tohigh brief overloads during the peak overload,

The RMS value for the peak load period should not be less than 90% of the integrated 1/2 h maximum demand.

#### EquivalentContinuousPriorLoad

Root Mean Squaure of the intervals occuring no more than 12 hours before the start of the load duration.

The equivalent continuous prior load is the RMS load obtained by over a chosen period of the day. Experience indicates that quite satisfactory results are obtained by considering the 12 hour periods preceding and following the peak and by selecting the larger of the two rmsvalues so produced.

#### EquivalentContinuousPriorLoadIntervalCount

Actual number of intervals collected, which should be 12 hourly intervals before the start of the load duration (DateMinLoadDuration).

> COUNT(ReadDate))

#### EquivalentContinuousPostLoad

Root Mean Squaure of the intervals occuring 1 to 12 hours afer the end of the load duration. See the above notes on EquivalentContinuousPriorLoad.

> SQRT(SUM(kVaSqaured)/COUNT(ReadDate))

#### EquivalentContinuousPostLoadIntervalCount

Actual number of intervals collected, which should be 12 hourly intervals after the end of the load duration (DateMaxLoadDuration).

> COUNT(ReadDate))

#### EquivalentContinuousMaxLoad 

The max value of EquivalentContinuousPriorLoad and EquivalentContinuousPostLoad AND divided by the kVA Rating multiplied by 100

> (@EquivalentContinuousMaxLoad / MAX(KVARating))*100

#### AmbientTemperatureF

Fahrenheit: The current temperature in F for the max kVA read value.

#### AmbientTemperatureC

Celsius: The temperature in AmbientTemperatureF converted to celsius.

#### TemperatureBelowThirtyMultiplier

> (30 - Tc), where Tc is the current temperature in celsius below 30C.

*Hey is there a flaw here, what happens when temp is negative?*

Adjustments for Chart:
-1.5% for each degree above 30°C
+1.0% for each degree below 30°C

Testing the calculation:

```sql
SELECT DISTINCT t.TemperatureF INTO #ConversionTest
from MDM.dbo.Temperature t

-- SET @AmbientTemperatureC = (@AmbientTemperatureF - 32) * 5/9
-- SET @TemperatureBelowThirtyMultiplier = (30 - @AmbientTemperatureC) 
-- SET @TemperatureAboveThirtyMultiplier = (@AmbientTemperatureC - 30)

SELECT
     TemperatureF F
    ,((TemperatureF - 32) * 5/9) Celsius
    ,CASE WHEN (TemperatureF - 32) * 5/9 > 30 THEN (((TemperatureF - 32) * 5/9) - 30)
        ELSE (30 - ((TemperatureF - 32) * 5/9))
    END As Multiplier
FROM #ConversionTest
ORDER BY 2 ASC

DROP TABLE #ConversionTest

```

What we need to check is the negative values create the correct multiplier.

F, Celsius, Multiplier
-2.4, -19.111111, 49.111111
86.0, 30.000000, 0.000000
95.0, 35.000000, 5.000000

Since we are below 30C, that is 30 + 19.1111 = 49.111111.  All is good.

#### TemperatureAboveThirtyMultiplier

> (Tc - 30), where Tc is the current temperature in celsius above 30C.

Adjustments for Chart:
-1.5% for each degree above 30°C
+1.0% for each degree below 30°C

#### DateMinLoadDuration

The point to the left of the kVAMax where the load duration begins. Used to help determine the Load Duration.

#### DateMaxLoadDuration

The point to the right of the kVAMax where the load duration ends. Used to help determine the Load Duration.

#### LoadDurationHours

Total lenght in hours of the load duration where the peak occurs.  We will
attempt to define the load duration where the kVA read value increases above the kVA rating
and ends where the last kVA rating is above the kVA rating.  Note during testing we found we
can have multiple peaks during a day (24 hr timespan) which can affect the LoadDurationHours.
Need more test cases to see how LoadDurationHours will affect the overall results in the Allowable Loading Matix.

#### AllowableLoadingPercentageColumn

The column 50, 75, 90 value we map our values to when determining if the transformer is overloaded. The columns (50,75,90)are choosen based on the RMS calculations max values for the prior load and post load percentages.

#### AllowableLoadingPercentage

The allowable load which is the max load acceptable for a Transformer for a period of time, determined by choosing the appropirate value from the Allowable Loading Matrix adjusted for temperature and altitude.

#### ActualLoadingPercentage

Calculation:

> (@kVAmax / @KVARating) * 100, value stored is stored as a percentage.

#### TransformerRatingPredictedChoice

The size of our new transfomer in kVA choosen by the algorithm.
The transformer should be a large transformer size if the transformer AllowableLoadingPercentage is lower
than the ActualLoadingPercentage.  The transformer should be a smaller value if the ActualLoadingPercentage and lower than the AllowableLoadingPercentage.  This value should be in the MDMTLA.dbo.TLAInventory.

If no match can be made this value can be NULL.

#### TransformerRatingPredictedLoadingPercentage 

The predicited percentage for the new transfomer sized in TransformerRatingPredictedChoice. 

Calculation:

> (@kVAmax / NEW @KVARating) * 100.

If no match can be made this value can be NULL.

#### CreatedDate

The date the process was ran in local time of the database server.

-- Root Mean Square to calculate the loading over 12 hours, what happens if we don't have 12 hours?????
-- IEEE pdf which references RMS
-- https://en.wikipedia.org/wiki/Root_mean_square
-- need mark up to show the math equation, for reference Equation 5, in IEEE Guid for Loading 
-- Mineral-Oil-Immersed Trabsformers and Step-Voltage Regualtors

## Interesting Quereies

Below are a set of queries used to initital review the data to check for inconsistencies.

*Using 'SELECT *' for brevity and place emphasis on the filter*

### Actual Number of Transformers

```sql
SELECT COUNT (DISTINCT TransformerIdentifier)
FROM MDMTLA.dbo.TLAReadHeader

$ 435
```

```sql
SELECT COUNT (TransformerIdentifier)
FROM MDMTLA.dbo.TLALoadingAnalysis

$ 435
```

### Transformers Analysis based on over sized vs under sized

Note, this query has flaws but does a quick job summarizing results for a quick reivew.
The flaws are because we have NULLS withing the data currently.

```sql
SELECT
    COUNT(*)
    ,CASE WHEN ActualLoadingPercentage > AllowableLoadingPercentage THEN 1
     ELSE 0
END AS IsOverLoaded
FROM MDMTLA.dbo.TLALoadingAnalysis
    GROUP BY
        CASE WHEN ActualLoadingPercentage > AllowableLoadingPercentage THEN 1
            ELSE 0
        END

$ count, IsOverLoaded
$ 225, 0
$ 210, 1
```

Note, we have the same number of TransformerIdentfiier's.

### Transformers which are over sized

A transformer which is over sized can be switched out for a smaller transformer.

The results of these two queries suggest we need more work on analysis on the data and the calculations.

```sql
SELECT *
FROM MDMTLA.dbo.TLALoadingAnalysis
WHERE TransformerRatingPredictedChoice > kVARating
ORDER BY TransformerRatingPredictedLoadingPercentage DESC

SELECT *
FROM MDMTLA.dbo.TLALoadingAnalysis
WHERE ISNULL(AllowableLoadingPercentage,0) <= ActualLoadingPercentage
```

OR

```sql
SELECT *
FROM MDMTLA.dbo.TLALoadingAnalysis
WHERE ActualLoadingPercentage > AllowableLoadingPercentage
ORDER BY TransformerRatingPredictedLoadingPercentage DESC
```

### Additional Checks Needed

- Scan all columns for NULLS
- Scan all columns for max and mins when numbers exist to check for values which are too large or too small.
 -- Multipliers too large, indicating issues with calculation or temperatures
 -- Percentages in the high 100s or 1000s
- You know do it all by hand which other languges already do as a standard practice.
- On and On...

Flaw - None of the Transformers stayed the same size, either the transformer went down a size or increased by a size.  Hmm?

```sql

SELECT * FROM MDMTLA.dbo.TLALoadingAnalysis
WHERE kVARating = TransformerRatingPredictedChoice

```

## References

- IEEE Guide for Loading Mineral- Oil-Immersed Transformers and  Step-Voltage Regulators, add Url or location to pdf.
- Life and Loading of Transformers power point, add url or location to pptx.
- https://en.wikipedia.org/wiki/Root_mean_square
