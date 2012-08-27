{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE OverloadedStrings #-}

import Data.Csv
import Network.HTTP.Conduit
import Control.Applicative
import Graphics.Blank
import GHC.Float
import LinReg
import Data.Time.Format
import System.Locale
import Data.Time.Calendar
import Data.Either
import Data.List
import Data.Hash.MD5

import qualified System.Directory           as SD
import qualified Data.ByteString.Char8      as DBC
import qualified Data.ByteString.Lazy       as DBL
import qualified Data.Vector                as V hiding ((++))
import           Control.Arrow                   hiding (loop)

order :: Int
order = 7

companies :: String
companies = "DTL IIN TPM SGT"

urls :: [(String,String)]
urls = flip map (words companies) $ \w -> (stockURL (w ++ ".AX") 2006 2013)

stockURL :: String -> Int -> Int -> (String,String)
stockURL s f t = (s,url)
  where url = "http://ichart.finance.yahoo.com/table.csv?s=" ++ s ++ "&d=6&e=12&f=" ++ show t ++ "&g=d&a=0&b=1&c=" ++ show f ++ "&ignore=.csv"

data PricePoint = PP Day Float deriving Show

instance FromField Day where
  parseField f = maybe (fail $ "Couldn't parse date " ++ str) return res
    where
      str = DBC.unpack f
      res = parseTime defaultTimeLocale "%Y-%m-%d" str

instance FromNamedRecord PricePoint where
  parseNamedRecord r = PP <$> r .: "Date" <*> r .: "Adj Close" -- Date,Open,High,Low,Close,Volume,Adj Close

httpCache :: String -> IO DBL.ByteString
httpCache url = do
  let filepath = "/tmp/asx" ++ md5s (Str url)
  fe <- SD.doesFileExist filepath
  if fe then DBL.readFile filepath
        else do csv <- simpleHttp url
                DBL.writeFile filepath csv
                return csv

main :: IO ()
main = do
  csvDatas <- mapM (httpCache . snd) urls

  plot (map fst urls) $ map (V.toList . snd) $ rights $ map decodeByName csvDatas

point :: PricePoint -> (Float,Float)
point (PP d p) = (fromIntegral $ toModifiedJulianDay d - 2011, p)

plot :: [String] -> [[PricePoint]] -> IO ()
plot names items = blankCanvas 5001 (draw names items)

lsrf :: Int -> [(Float,Float)] -> [Float]
lsrf o l = map double2Float $ lsr o (map (float2Double *** float2Double) l)

sketch :: ((Float,Float) -> (Float,Float)) -> [(Float,Float)] -> Canvas ()
sketch f l = beginPath () >> moveTo (f $ head l) >> mapM_ (lineTo . f) l

{-
dot :: String -> ((Float,Float) -> (Float,Float)) -> (Float,Float) -> Canvas ()
dot c f p = do
  save ()
  beginPath ()
  translate (f p)
  arc (0, 0, 2, 0, 2 * pi, False)
  strokeStyle c
  lineWidth 2
  stroke
  restore ()
-}

adjust :: (Float, Float) -> [(Float, Float)] -> (Float, Float) -> (Float, Float)
adjust (w,h) l = f
  where
    ((lx,ly),(hx,hy)) = bounds l
    dx = hx - lx
    dy = hy - ly
    f (x,y) = (w * (x - lx) / dx, h * (hy - y) / dy)

bounds :: [(Float,Float)] -> ((Float,Float),(Float,Float))
bounds = ((minimum *** minimum) &&& (maximum *** maximum)) . unzip

functionData :: [Float] -> [(Float, Float)]
functionData cs = map (id &&& poly cs) [0..]

poly :: [Float] -> Float -> Float
poly cs x = double2Float $ poly' (map float2Double cs) (float2Double x)
  where
    poly' :: [Double] -> Double -> Double
    poly' cs' x' = sum $ zipWith (*) cs' $ map (x'**) [0..]

colors :: [String]
colors = cycle $ words "#CC3300 #CC9900 #99CC00 #33CC00 #00CC33 #00CC99 #0099CC #0033CC #470AFF #7547FF #C2FF0A"

constraints :: [PricePoint] -> [(Float, Float)]
constraints items = map (id &&& fun) (map fst points)
  where points = map point items
        fun    = poly consts
        consts = lsrf order points

draw :: [String] -> [[PricePoint]] -> Context -> IO ()
draw names mitems context =
  do screenSize@(wwid,whei) <- send context size

     let adjusts  = map (adjust screenSize) (zipWith (++) points fitted)
         points   = map (map point) mitems
         fitted   = map constraints mitems

     send context $ do
       fillStyle "#111111"
       fillRect (0,0,wwid,whei)

     flip mapM_ (zip4 adjusts fitted points colors) $ \(adjuster,f,p,c) -> do

       send context $ do
          strokeStyle c
          sketch adjuster f
          lineWidth 7
          stroke

       send context $ do
          strokeStyle c
          sketch adjuster p
          lineWidth 1
          stroke

     flip mapM_ (zip3 [1..] names colors) $ \(ind,name,c) -> do

       send context $ do

         save ()
         fillStyle "#000000"
         fillRect (25, 25 + 60 * ind, 180, 50)

         fillStyle c
         fillRect (30, 30 + 60 * ind, 40, 40)
         font "20pt arial"
         fillText(name, 80, 62 + 60 * ind)
         restore ()

     send context $ do
        save ()
        fillStyle "#000000"
        fillRect (5, 5, 500, 65)
        fillStyle "#DDDDDD"
        font "30pt times"
        fillText("Adjusted EOD Stock Prices", 20, 50)
        restore ()