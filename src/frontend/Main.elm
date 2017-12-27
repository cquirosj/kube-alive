import Html exposing (..)
import Html.Attributes exposing (..)
import Html.Events exposing (..)
import String.Format exposing (format1)
import WebSocket
import Http exposing (get, send)
import KubernetesApiModel exposing (KubernetesResultMetadata, KubernetesPodResult, KubernetesPodItem, KubernetesPodMetadata, KubernetesLabels, KubernetesPodStatus, KubernetesPodCondition, KubernetesPodUpdate)
import KubernetesApiDecoder exposing (decodeKubernetesPodResult, decodeKubernetesPodUpdate)
import Json.Decode exposing (decodeString)

main =
  Html.program
    { init = init
    , view = view
    , update = update
    , subscriptions = subscriptions
    }

-- MODEL

type alias PodInfo =
    { name: String
    , uid: String
    , app: String
    , status: String
    }

type alias LoadBalancingModel =
    { pods: List PodInfo
    }

type alias Model =
  {   podList : List PodInfo
    , podListResourceVersion : String
    , debugText : String
  }

init : (Model, Cmd Msg)
init =
  (Model [] "" "(Loading)", Http.send PodList (Http.get "http://192.168.178.80:83/api/v1/namespaces/default/pods" decodeKubernetesPodResult))

-- UPDATE

type Msg = PodList (Result Http.Error KubernetesPodResult) | PodUpdate String

makePodInfoStatus : KubernetesPodItem -> String
makePodInfoStatus item =
    case item.metadata.deletionTimestamp of 
        Just _ -> "Terminating"
        Nothing -> item.status.phase

makePodInfo : KubernetesPodItem -> PodInfo
makePodInfo item =
    PodInfo item.metadata.name item.metadata.uid item.metadata.labels.app (makePodInfoStatus item)

makePodList : KubernetesPodResult -> List PodInfo
makePodList newPodList =
    List.map makePodInfo newPodList.items

updatePodInfo : KubernetesPodUpdate -> PodInfo -> PodInfo
updatePodInfo podUpdate podInfo =
    if podUpdate.object.metadata.uid == podInfo.uid then
        { podInfo | status = makePodInfoStatus podUpdate.object }
    else
        podInfo

selectAllPodsExcept : KubernetesPodUpdate -> PodInfo -> Bool
selectAllPodsExcept podUpdate podInfo =
    podUpdate.object.metadata.uid /= podInfo.uid

updatePodList : List PodInfo -> KubernetesPodUpdate -> List PodInfo
updatePodList podList podUpdate =
    case podUpdate.updateType of
        "MODIFIED" ->
            List.map (updatePodInfo podUpdate) podList
        "DELETED" ->
            List.filter (selectAllPodsExcept podUpdate) podList
        "ADDED" ->
            (makePodInfo podUpdate.object) :: podList
        _ ->
            podList

update : Msg -> Model -> (Model, Cmd Msg)
update msg model =
  case msg of
    PodList (Ok newPodList) ->
        ({ model | debugText = "Loaded.", podList = makePodList newPodList, podListResourceVersion = newPodList.metadata.resourceVersion }, Cmd.none)
    PodList (Err _) ->
        ({ model | debugText = "Fetch error" }, Cmd.none)
    PodUpdate jsonResponse ->
        let
            parseResult = (decodeString decodeKubernetesPodUpdate jsonResponse)
        in 
            case parseResult of
                Ok podUpdates ->
                    ({ model | podList = (updatePodList model.podList podUpdates) }, Cmd.none)
                Err errorMessage ->
                    ({ model | debugText = errorMessage }, Cmd.none)

-- SUBSCRIPTIONS

subscriptions : Model -> Sub Msg
subscriptions model =
    case model.podListResourceVersion of
        "" ->
            Sub.none
        version ->
            WebSocket.listen (format1 "ws://192.168.178.80:83/api/v1/namespaces/default/pods?resourceVersion={1}&watch=true" model.podListResourceVersion) PodUpdate

-- VIEW

renderPodRow : PodInfo -> Html msg
renderPodRow podInfo =
    tr [] [
        td [] [ text podInfo.name ],
        td [] [ text podInfo.status ]
    ]

view : Model -> Html Msg
view model =
  div []
    [ 
        text model.debugText,
        table [] (List.map renderPodRow model.podList) 
    ]

