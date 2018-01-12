-- | Module for command-line utilites, parsers and convenient handlers.

module Pos.Client.CLI.Util
       ( printFlags
       , printInfoOnStart
       , attackTypeParser
       , attackTargetParser
       , defaultLoggerConfig
       , readLoggerConfig
       , stakeholderIdParser
       , dumpGenesisData
       ) where

import           Universum

import qualified Data.ByteString.Lazy as BSL
import           Formatting (sformat, shown, (%))
import           Mockable (CurrentTime, Mockable, currentTime)
import           System.Wlog (LoggerConfig (..), WithLogger, logInfo, parseLoggerConfig,
                              productionB)
import           Text.Parsec (parserFail, try)
import qualified Text.Parsec.Char as P
import qualified Text.Parsec.Text as P

import           Pos.Binary.Core ()
import           Pos.Client.CLI.NodeOptions (CommonNodeArgs (..))
import           Pos.Client.CLI.Options (configurationOptions)
import           Pos.Core (StakeholderId, Timestamp (..))
import           Pos.Core.Configuration (HasConfiguration, canonicalGenesisJson, genesisData,
                                         prettyGenesisJson)
import           Pos.Core.Genesis (gdStartTime)
import           Pos.Crypto (decodeAbstractHash)
import           Pos.Security.Params (AttackTarget (..), AttackType (..))
import           Pos.Util.AssertMode (inAssertMode)
import           Pos.Util.TimeWarp (addrParser)

printFlags :: WithLogger m => m ()
printFlags = do
    inAssertMode $ logInfo "Asserts are ON"

printInfoOnStart ::
       (HasConfiguration, WithLogger m, Mockable CurrentTime m)
    => CommonNodeArgs
    -> m ()
printInfoOnStart cArgs = do
    printFlags
    t <- currentTime
    mapM_ logInfo $
        [ sformat ("System start time is " % shown) $ gdStartTime genesisData
        , sformat ("Current time is "%shown) (Timestamp t)
        , sformat ("Using configs and genesis:\n"%shown)
                  (configurationOptions (commonArgs cArgs))
        ]

attackTypeParser :: P.Parser AttackType
attackTypeParser = P.string "No" >>
    AttackNoBlocks <$ (P.string "Blocks") <|>
    AttackNoCommitments <$ (P.string "Commitments")

stakeholderIdParser :: P.Parser StakeholderId
stakeholderIdParser = do
    token <- some P.alphaNum
    either (parserFail . toString) return $
        decodeAbstractHash (toText token)

attackTargetParser :: P.Parser AttackTarget
attackTargetParser =
    (PubKeyAddressTarget <$> Text.Parsec.try stakeholderIdParser) <|>
    (NetworkAddressTarget <$> addrParser)

-- | Default logger config. Will be used if `--log-config` argument is
-- not passed.
defaultLoggerConfig :: LoggerConfig
defaultLoggerConfig = productionB

-- | Reads logger config from given path. By default returns
-- 'defaultLoggerConfig'.
readLoggerConfig :: MonadIO m => Maybe FilePath -> m LoggerConfig
readLoggerConfig = maybe (return defaultLoggerConfig) parseLoggerConfig

-- | Dump our 'GenesisData' into a file.
dumpGenesisData ::
       (HasConfiguration, MonadIO m, WithLogger m) => Bool -> FilePath -> m ()
dumpGenesisData canonical path = do
    let (canonicalJsonBytes, jsonHash) = canonicalGenesisJson genesisData
    let prettyJsonStr = prettyGenesisJson genesisData
    logInfo $ sformat ("Writing JSON with hash "%shown%" to "%shown) jsonHash path
    liftIO $ case canonical of
        True  -> BSL.writeFile path canonicalJsonBytes
        False -> writeFile path (toText prettyJsonStr)
