import SwiftUI

@main
struct PostExplorerApp: App {
    var body: some Scene {
        WindowGroup {
            PostsView(viewModel: PostsViewModel(client: APIClient()))
        }
    }
}

// MARK: - Models

struct Post: Codable, Identifiable, Hashable {
    let id: Int
    let userId: Int
    let title: String
    let body: String
}

struct Comment: Codable, Identifiable, Hashable {
    let id: Int
    let postId: Int
    let name: String
    let email: String
    let body: String
}

struct User: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let username: String
    let email: String
}

// MARK: - API & Networking

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case decodingFailed(Error)
    case serverError(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "არასწორი URL მისამართი."
        case .invalidResponse:
            return "სერვერიდან მიღებულია არასწორი პასუხი."
        case .decodingFailed(let error):
            return "მონაცემების დეკოდირება ვერ მოხერხდა: \(error.localizedDescription)"
        case .serverError(let statusCode):
            return "სერვერის შეცდომა (კოდი: \(statusCode))."
        }
    }
}

protocol APIClientProtocol {
    func fetchPosts() async throws -> [Post]
    func fetchPost(id: Int) async throws -> Post
    func fetchComments(postID: Int) async throws -> [Comment]
    func fetchUser(id: Int) async throws -> User
    func fetchPosts(userID: Int) async throws -> [Post]
}

final class APIClient: APIClientProtocol {
    private let baseURL = "https://jsonplaceholder.typicode.com"
    
    private func fetch<T: Decodable>(_ endpoint: String) async throws -> T {
        guard let url = URL(string: baseURL + endpoint) else {
            throw APIError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
        
        do {
            let decodedData = try JSONDecoder().decode(T.self, from: data)
            return decodedData
        } catch {
            throw APIError.decodingFailed(error)
        }
    }
    
    func fetchPosts() async throws -> [Post] {
        try await fetch("/posts")
    }
    
    func fetchPost(id: Int) async throws -> Post {
        try await fetch("/posts/\(id)")
    }
    
    func fetchComments(postID: Int) async throws -> [Comment] {
        try await fetch("/comments?postId=\(postID)")
    }
    
    func fetchUser(id: Int) async throws -> User {
        try await fetch("/users/\(id)")
    }
    
    func fetchPosts(userID: Int) async throws -> [Post] {
        try await fetch("/posts?userId=\(userID)")
    }
}

// MARK: - State Management

enum ViewState<T> {
    case idle
    case loading
    case loaded(T)
    case error(String)
}

// MARK: - Student 1: Posts List View & ViewModel

@MainActor
final class PostsViewModel: ObservableObject {
    @Published private(set) var state: ViewState<[Post]> = .idle
    private let client: APIClientProtocol
    
    init(client: APIClientProtocol) {
        self.client = client
    }
    
    func loadPosts() async {
        state = .loading
        do {
            let posts = try await client.fetchPosts()
            state = .loaded(posts)
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}

struct PostsView: View {
    @StateObject var viewModel: PostsViewModel
    
    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.state {
                case .idle, .loading:
                    ProgressView("იტვირთება პოსტები...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .loaded(let posts):
                    List(posts) { post in
                        NavigationLink(value: post) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(post.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(post.body)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.plain)
                case .error(let message):
                    VStack(spacing: 12) {
                        Text(message)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding()
                        Button("თავიდან ცდა") {
                            Task {
                                await viewModel.loadPosts()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("პოსტები")
            .navigationDestination(for: Post.self) { post in
                PostDetailView(postId: post.id, client: APIClient())
            }
            .navigationDestination(for: Int.self) { userId in
                UserProfileView(userId: userId, client: APIClient())
            }
        }
        .task {
            if case .idle = viewModel.state {
                await viewModel.loadPosts()
            }
        }
    }
}

// MARK: - Student 2: Post Detail View & ViewModel

struct PostDetailData {
    let post: Post
    let comments: [Comment]
}

@MainActor
final class PostDetailViewModel: ObservableObject {
    @Published private(set) var state: ViewState<PostDetailData> = .idle
    private let postId: Int
    private let client: APIClientProtocol
    
    init(postId: Int, client: APIClientProtocol) {
        self.postId = postId
        self.client = client
    }
    
    func loadData() async {
        state = .loading
        do {
            async let fetchedPost = client.fetchPost(id: postId)
            async let fetchedComments = client.fetchComments(postID: postId)
            
            let post = try await fetchedPost
            let comments = try await fetchedComments
            
            state = .loaded(PostDetailData(post: post, comments: comments))
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}

struct PostDetailView: View {
    @StateObject private var viewModel: PostDetailViewModel
    
    init(postId: Int, client: APIClientProtocol) {
        _viewModel = StateObject(wrappedValue: PostDetailViewModel(postId: postId, client: client))
    }
    
    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("იტვირთება დეტალები...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let data):
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(data.post.title)
                                .font(.title2)
                                .bold()
                            Text(data.post.body)
                                .font(.body)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                        
                        NavigationLink(value: data.post.userId) {
                            Label("ავტორის პროფილი", systemImage: "person.circle.fill")
                                .font(.headline)
                                .foregroundColor(.accentColor)
                        }
                    }
                    
                    Section(header: Text("კომენტარები (\(data.comments.count))")) {
                        ForEach(data.comments) { comment in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(comment.name)
                                    .font(.subheadline)
                                    .bold()
                                Text(comment.email)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(comment.body)
                                    .font(.caption)
                                    .padding(.top, 2)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            case .error(let message):
                VStack(spacing: 12) {
                    Text(message)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("თავიდან ცდა") {
                        Task {
                            await viewModel.loadData()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("პოსტის დეტალები")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if case .idle = viewModel.state {
                await viewModel.loadData()
            }
        }
    }
}

// MARK: - Student 3: User Profile View & ViewModel

struct UserProfileData {
    let user: User
    let posts: [Post]
}

@MainActor
final class UserProfileViewModel: ObservableObject {
    @Published private(set) var state: ViewState<UserProfileData> = .idle
    private let userId: Int
    private let client: APIClientProtocol
    
    init(userId: Int, client: APIClientProtocol) {
        self.userId = userId
        self.client = client
    }
    
    func loadData() async {
        state = .loading
        do {
            async let fetchedUser = client.fetchUser(id: userId)
            async let fetchedPosts = client.fetchPosts(userID: userId)
            
            let user = try await fetchedUser
            let posts = try await fetchedPosts
            
            state = .loaded(UserProfileData(user: user, posts: posts))
        } catch {
            state = .error(error.localizedDescription)
        }
    }
}

struct UserProfileView: View {
    @StateObject private var viewModel: UserProfileViewModel
    
    init(userId: Int, client: APIClientProtocol) {
        _viewModel = StateObject(wrappedValue: UserProfileViewModel(userId: userId, client: client))
    }
    
    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("იტვირთება პროფილი...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let data):
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(data.user.name)
                                .font(.title2)
                                .bold()
                            Text("@\(data.user.username)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(data.user.email)
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    Section(header: Text("ავტორის პოსტები (\(data.posts.count))")) {
                        ForEach(data.posts) { post in
                            NavigationLink(value: post) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(post.title)
                                        .font(.headline)
                                        .lineLimit(1)
                                    Text(post.body)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            case .error(let message):
                VStack(spacing: 12) {
                    Text(message)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding()
                    Button("თავიდან ცდა") {
                        Task {
                            await viewModel.loadData()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("ავტორის პროფილი")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if case .idle = viewModel.state {
                await viewModel.loadData()
            }
        }
    }
}
