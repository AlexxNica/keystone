module Model exposing (..)

import Combine exposing (..)
import Combine.Char exposing (..)
import List exposing (concat)


type alias Model =
    List Declaration


type alias BlockName =
    String


type ModelContainer
    = Raw
    | Markdown


type Statement
    = SFulfill String
    | SRequire String
    | SInstance String String
    | SConnect String String String


type Declaration
    = DInterface String
    | DComponent String (List Statement)
    | DSystem String (List Statement)


comment : Parser s String
comment =
    regex "--[^\n]*"


skippables : Parser s (List String)
skippables =
    many (comment <|> whitespace)


name : Parser s String
name =
    whitespace *> regex "[a-zA-Z0-9_-]+" <* whitespace


decl : String -> Parser BlockName res -> Parser BlockName res
decl s p =
    let
        blockStart _ =
            whitespace
                *> string s
                *> name
                <* string "is"
                <* whitespace

        captureName n =
            putState n

        blockEnd name =
            whitespace
                *> string "end"
                *> whitespace
                *> string name
                <* string ";"
    in
        (blockStart s >>= captureName)
            *> (skippables *> p <* skippables)
            <* withState blockEnd


fulfill : Parser s Statement
fulfill =
    SFulfill
        <$> (string "fulfill"
                *> whitespace
                *> name
                <* string ";"
            )


require : Parser s Statement
require =
    SRequire
        <$> (string "require"
                *> whitespace
                *> name
                <* string ";"
            )


instance : Parser s Statement
instance =
    SInstance
        <$> (name <* (string ":" *> whitespace))
        <*> (name <* string ";")


connection : Parser s Statement
connection =
    SConnect
        <$> (string "connect" *> name)
        <*> (string "to" *> name)
        <*> (string "via" *> name <* string ";")


system : Parser BlockName Declaration
system =
    let
        allowedStatements =
            [ instance, connection, fulfill, require ]

        build n =
            DSystem n <$> many (skippables *> choice allowedStatements)
    in
        decl "system" (withState build)


component : Parser BlockName Declaration
component =
    let
        build n =
            DComponent n <$> many (skippables *> choice [ fulfill, require ])
    in
        decl "component" (withState build)


interface : Parser BlockName Declaration
interface =
    decl "interface" (withState (\n -> succeed (DInterface n)))


block : Parser BlockName Declaration
block =
    skippables *> choice [ component, system, interface ] <* skippables


rawModel : Parser BlockName Model
rawModel =
    manyTill block end


markdownModel : Parser BlockName Model
markdownModel =
    concat
        <$> manyTill
                ((manyTill anyChar (string "```keystone")
                    *> manyTill block (whitespace *> string "```")
                 )
                    <* many anyChar
                )
                end


formatError : List String -> InputStream -> String
formatError ms stream =
    let
        location =
            currentLocation stream

        separator =
            " |> "

        expectationSeparator =
            "\n  * "

        separatorOffset =
            String.length separator

        padding =
            location.column + separatorOffset
    in
        "Parse error around line "
            ++ toString location.line
            ++ ":\n\n"
            ++ separator
            ++ location.source
            ++ "\n"
            ++ String.padLeft padding ' ' "^"
            ++ "\nI expected one of the following:\n"
            ++ expectationSeparator
            ++ String.join expectationSeparator ms


parse : ModelContainer -> String -> Result String Model
parse c s =
    let
        parser =
            if c == Raw then
                rawModel
            else
                markdownModel
    in
        case Combine.runParser parser "<toplevel>" s of
            Ok ( _, _, e ) ->
                Ok e

            Err ( _, stream, ms ) ->
                Err <| formatError ms stream
