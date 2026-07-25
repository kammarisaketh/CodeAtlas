from collections.abc import AsyncIterator
import json

from app.schemas.repositories import RepositoryFileRead, RepositorySearchResult


class ChatService:
    async def stream_answer(
        self,
        question: str,
        files: list[RepositoryFileRead],
        search_results: list[RepositorySearchResult],
    ) -> AsyncIterator[str]:
        if not search_results:
            yield "event: token\n"
            yield f"data: {json.dumps('I could not find enough indexed repository evidence to answer: ' + question)}\n\n"
            yield "event: done\n"
            yield "data: {\"confidence\":\"insufficient_evidence\",\"citations\":[]}\n\n"
            return

        top_results = search_results[:3]
        cited_paths = ", ".join(f"{result.path}:{result.start_line}" for result in top_results)
        answer = (
            f"Based on the indexed repository content, the strongest evidence for '{question}' "
            f"is in {cited_paths}. The matching snippets point to the files and line ranges "
            "returned in the citations, so the answer should be treated as repository-grounded rather than general advice."
        )
        yield "event: token\n"
        yield f"data: {json.dumps(answer)}\n\n"
        yield "event: done\n"
        yield "data: " + json.dumps(
            {
                "confidence": "medium" if files else "low",
                "citations": [
                    {
                        "file_id": str(result.file_id),
                        "path": result.path,
                        "start_line": result.start_line,
                        "end_line": result.end_line,
                        "snippet": result.snippet,
                    }
                    for result in top_results
                ],
            }
        ) + "\n\n"


chat_service = ChatService()
