import type { EvaluationResult } from "../api/client";

export type ProviderId = "aws-rekognition" | "google-cloud-vision";

export interface Provider {
  id: ProviderId;
  name: string;
  shortName: string;
  status: "AWS real" | "Google real" | "Backend MOCK";
}

export const providers: Provider[] = [
  {
    id: "aws-rekognition",
    name: "AWS Rekognition",
    shortName: "AWS",
    status: "AWS real"
  },
  {
    id: "google-cloud-vision",
    name: "Google Cloud Vision",
    shortName: "Google",
    status: "Google real"
  }
];

export const evaluationResults: EvaluationResult[] = ["CORRECT", "PARTIAL", "WRONG", "INCONCLUSIVE"];
