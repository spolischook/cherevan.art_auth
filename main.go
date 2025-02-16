package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"log"
	"os"

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
)

var (
	googleOauthConfig *oauth2.Config
)

type StateData struct {
	RedirectURL string `json:"redirect_url"`
}

func generateState(redirectURL string) (string, error) {
	state := StateData{
		RedirectURL: redirectURL,
	}
	jsonData, err := json.Marshal(state)
	if err != nil {
		return "", err
	}
	return base64.URLEncoding.EncodeToString(jsonData), nil
}

func parseState(state string) (string, error) {
	jsonData, err := base64.URLEncoding.DecodeString(state)
	if err != nil {
		return "", err
	}
	var stateData StateData
	if err := json.Unmarshal(jsonData, &stateData); err != nil {
		return "", err
	}
	return stateData.RedirectURL, nil
}

func init() {
	clientID := os.Getenv("GOOGLE_CLIENT_ID")
	clientSecret := os.Getenv("GOOGLE_CLIENT_SECRET")
	redirectURL := os.Getenv("GOOGLE_REDIRECT_URL")

	if clientID == "" || clientSecret == "" || redirectURL == "" {
		log.Fatal("Missing required environment variables")
	}

	googleOauthConfig = &oauth2.Config{
		ClientID:     clientID,
		ClientSecret: clientSecret,
		RedirectURL:  redirectURL,
		Scopes: []string{
			"openid",
			"profile",
			"email",
		},
		Endpoint: google.Endpoint,
	}
}

func handleRequest(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	switch request.Path {
	case "/auth":
		redirectURL := request.QueryStringParameters["redirect_url"]
		if redirectURL == "" {
			return events.APIGatewayProxyResponse{
				StatusCode: 400,
				Body:       `{"error": "redirect_url parameter is required"}`,
			}, nil
		}

		state, err := generateState(redirectURL)
		if err != nil {
			return events.APIGatewayProxyResponse{
				StatusCode: 500,
				Body:       fmt.Sprintf(`{"error": "failed to generate state: %v"}`, err),
			}, nil
		}

		url := googleOauthConfig.AuthCodeURL(
			state,
			oauth2.SetAuthURLParam("prompt", "select_account"),
			oauth2.SetAuthURLParam("access_type", "online"),
			oauth2.SetAuthURLParam("response_type", "code"),
			oauth2.SetAuthURLParam("include_granted_scopes", "true"),
		)
		return events.APIGatewayProxyResponse{
			StatusCode: 302,
			Headers: map[string]string{
				"Location": url,
			},
		}, nil

	case "/callback":
		state := request.QueryStringParameters["state"]
		if state == "" {
			return events.APIGatewayProxyResponse{
				StatusCode: 400,
				Body:       `{"error": "state parameter is required"}`,
			}, nil
		}

		redirectURL, err := parseState(state)
		if err != nil {
			return events.APIGatewayProxyResponse{
				StatusCode: 400,
				Body:       fmt.Sprintf(`{"error": "invalid state parameter: %v"}`, err),
			}, nil
		}

		code := request.QueryStringParameters["code"]
		if code == "" {
			return events.APIGatewayProxyResponse{
				StatusCode: 400,
				Body:       `{"error": "code parameter is required"}`,
			}, nil
		}

		token, err := googleOauthConfig.Exchange(ctx, code)
		if err != nil {
			return events.APIGatewayProxyResponse{
				StatusCode: 500,
				Body:       fmt.Sprintf(`{"error": "failed to exchange token: %v"}`, err),
			}, nil
		}

		// Return token in URL fragment
		return events.APIGatewayProxyResponse{
			StatusCode: 302,
			Headers: map[string]string{
				"Location": fmt.Sprintf("%s#access_token=%s", redirectURL, token.AccessToken),
			},
		}, nil

	default:
		return events.APIGatewayProxyResponse{
			StatusCode: 404,
			Body:       `{"error": "not found"}`,
		}, nil
	}
}

func main() {
	lambda.Start(handleRequest)
}
