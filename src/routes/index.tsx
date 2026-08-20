import { createFileRoute } from "@tanstack/react-router";
import { LabApp } from "@/components/lab/lab-app";

export const Route = createFileRoute("/")({ component: LabApp });
