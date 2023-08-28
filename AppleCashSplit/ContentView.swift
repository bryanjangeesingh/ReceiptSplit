import MessageUI
import SwiftUI

struct ContentView: View {
    @State private var isImagePickerPresented: Bool = false
    @State private var selectedImage: UIImage? = nil
    @State private var isLoading: Bool = false
    @State private var serverResponse: String? = nil
    @State private var showResponsePage: Bool = false
    @AppStorage("friends") var friendsData: Data = Data()
    @State private var friends: [Friend] = []
    @State private var showAddFriendForm: Bool = false
    @State private var showFriendsList: Bool = false
    @State private var isAppOpenedForFirstTime: Bool = UserDefaults.standard.bool(forKey: "isAppOpenedForFirstTime")
    @State private var dataManager: DataManager

    init() {
        let friendsData: Data = UserDefaults.standard.data(forKey: "friends") ?? Data()
        let friends: [Friend]? = try? JSONDecoder().decode([Friend].self, from: friendsData)

        _dataManager = State(initialValue: DataManager(friends: friends ?? []))
        dataManager.clearTabs()

        let updatedFriends = dataManager.getFriends()

        // update storage of friends so their tabs are reset to nil
        if let encodedFriends = try? JSONEncoder().encode(updatedFriends) {
            UserDefaults.standard.set(encodedFriends, forKey: "friends")
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                HStack {
                    NavigationLink(destination: FriendsListView(friends: $friends), isActive: $showFriendsList) {
                        Button(action: {
                            showFriendsList = true
                        }) {
                            Image(systemName: "person.2") // SF Symbol for friends icon
                                .resizable()
                                .frame(width: 30, height: 24)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing)

                    NavigationLink(destination: AddFriendFormView(friends: $friends), isActive: $showAddFriendForm) {
                        Button(action: {
                            showAddFriendForm = true
                        }) {
                            Image(systemName: "person.badge.plus") // SF Symbol for add friend icon
                                .resizable()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.white)
                        }
                    }
                    .padding(.trailing)

                    Button(action: {
                        isImagePickerPresented.toggle()
                    }) {
                        Image(systemName: "photo.on.rectangle.angled") // SF Symbol for gallery icon
                            .resizable()
                            .frame(width: 30, height: 24)
                            .foregroundColor(.white)
                    }
                    .padding(.trailing)
                }

                Spacer() // Pushes the text down

                Text("Upload Receipts")
                    .foregroundColor(.white)
                    .font(Font.custom("Ysabeau", size: 35))
                    .padding(.top, 150) // Adjust as needed

                Spacer()

                if let selectedImage = selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    Button("Scan") {
                        uploadImage()
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                } else {
                    Image("bg2")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                }

                NavigationLink(destination: ResponseView(response: serverResponse ?? "", friends: friends), isActive: $showResponsePage) {
                    EmptyView()
                }

                Spacer()
            }
            .sheet(isPresented: $isImagePickerPresented) {
                ImagePicker(image: $selectedImage)
            }
        }
        .onAppear {
            if let savedFriends = try? JSONDecoder().decode([Friend].self, from: friendsData) {
                friends = savedFriends
            }

            if isAppOpenedForFirstTime == false {
                let newFriend = Friend(name: "YOU", phoneNumber: nil, tab: nil)
                friends.append(newFriend)
                UserDefaults.standard.set(true, forKey: "isAppOpenedForFirstTime")
            }
        }
        .onChange(of: friends) { newFriends in
            if let encoded = try? JSONEncoder().encode(newFriends) {
                friendsData = encoded
            }
        }
    }

    func uploadImage() {
        guard let uiImage = selectedImage,
              let imageData: Data = uiImage.jpegData(compressionQuality: 0.1) else {
            print("Image conversion failed")
            return
        }

        let url: URL = URL(string: "https://brytech.pythonanywhere.com/upload")!

        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let boundaryPrefix = "--\(boundary)\r\n"
        body.append(boundaryPrefix.data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        isLoading = true

        URLSession.shared.dataTask(with: request, completionHandler: { data, _, _ in
            guard let data = data else {
                print("invalid data")
                return
            }
            let responseStr: String = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self.isLoading = false
                self.serverResponse = responseStr
                print(responseStr)
                self.showResponsePage = true
            }
        })
        .resume()
    }

    struct ImagePicker: UIViewControllerRepresentable {
        @Binding var image: UIImage?
        @Environment(\.presentationMode) private var presentationMode

        func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_ uiViewController: UIImagePickerController, context: UIViewControllerRepresentableContext<ImagePicker>) {}

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
            let parent: ImagePicker

            init(_ parent: ImagePicker) {
                self.parent = parent
            }

            func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
                if let uiImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
                    parent.image = uiImage
                }
                parent.presentationMode.wrappedValue.dismiss()
            }
        }
    }

    struct ResponseView: View {
        var friends: [Friend]
        @State private var items: [Item] = []
        @State private var showAssignTabToFriend: Bool = false // State to manage navigation
        @State private var subtotal: Double = 0.0
        @State private var tax: Double = 0.0
        @State private var total: Double = 0.0
        @State private var tip: Double = 0.0

        var isValid: Bool {
            return subtotal != 0 && tax != 0 && total != 0
        }

        func saveData() -> SavedData {
            let savedItems = items.map { Item(name: $0.name, quantity: $0.quantity ?? 0.0, totalPrice: $0.totalPrice) }
            return SavedData(items: savedItems, subtotal: subtotal, tax: tax, total: total, tip: tip)
        }

        init(response: String, friends: [Friend]) {
            self.friends = friends
            if let data = response.data(using: .utf8) {
                do {
                    let decodedResponse = try JSONDecoder().decode([MyStruct].self, from: data)
                    let firstResponse = decodedResponse.first
                    _subtotal = State(initialValue: firstResponse?.subtotal ?? 0.0)
                    _tax = State(initialValue: firstResponse?.tax ?? 0.0)
                    _total = State(initialValue: firstResponse?.total ?? 0.0)
                    _tip = State(initialValue: firstResponse?.tip ?? 0.0)
                    _items = State(initialValue: firstResponse?.items ?? []) // Setting items
                } catch {
                    print("Decoding error: \(error)")
                }
            }
        }

        // Custom number formatter that allows two decimal places
        private let myNumberFormatter: NumberFormatter = {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 2
            formatter.maximumFractionDigits = 2
            return formatter
        }()

        struct MyStruct: Codable {
            let subtotal: Double
            let tax: Double
            let total: Double
            let tip: Double
            let items: [Item]

            private enum CodingKeys: String, CodingKey {
                case subtotal = "Subtotal"
                case tax = "Tax"
                case total = "Total"
                case tip = "Tip"
                case items = "Items" // Update this line to match the JSON key
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)

                subtotal = try MyStruct.decodeValue(from: container, forKey: .subtotal)
                tax = try MyStruct.decodeValue(from: container, forKey: .tax)
                total = try MyStruct.decodeValue(from: container, forKey: .total)
                tip = try MyStruct.decodeValue(from: container, forKey: .tip)
                items = try container.decode([Item].self, forKey: .items) // Add this line
            }

            private static func decodeValue(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Double {
                if let doubleValue = try? container.decode(Double.self, forKey: key) {
                    return doubleValue
                } else if let stringValue = try? container.decode(String.self, forKey: key),
                          stringValue != "N/A",
                          let doubleValueFromString = Double(stringValue) {
                    return doubleValueFromString
                } else {
                    return 0.0 // Default value
                }
            }
        }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading) {
                    Text("Confirm the Name, Quantity, and Price")
                        .font(Font.custom("Ysabeau", size: 20))

                    HStack {
                        Text("Name")
                            .fontWeight(.bold)
                            .font(Font.custom("Ysabeau", size: 18))

                        Spacer()
                        Text("Quantity")
                            .fontWeight(.bold)
                            .frame(width: 75)
                            .font(Font.custom("Ysabeau", size: 18))

                        Spacer()
                        Text("Total Price")
                            .fontWeight(.bold)
                            .frame(width: 100)
                            .font(Font.custom("Ysabeau", size: 18))
                    }
                    .padding()

                    ForEach(0 ..< items.count, id: \.self) { index in
                        HStack {
                            TextField("Name", text: $items[index].name)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(Font.custom("Ysabeau", size: 20))
                            Spacer()
                            TextField("Quantity", value: Binding(
                                get: { items[index].quantity ?? 0.0 },
                                set: { newValue in items[index].quantity = newValue }
                            ), formatter: NumberFormatter())
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 50)
                                .font(Font.custom("Ysabeau", size: 20))
                            Spacer()
                            TextField("Total Price", value: $items[index].totalPrice, formatter: myNumberFormatter)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .frame(width: 100)
                                .font(Font.custom("Ysabeau", size: 20))
                        }
                        .padding(.horizontal)
                    }

                    Button("Add Item") {
                        items.append(Item(name: "", quantity: 0.0, totalPrice: 0.0))
                    }

                    // Placeholders for alignment
                    HStack {
                        Spacer()
                        Spacer()
                        VStack(alignment: .trailing) {
                            HStack {
                                Text("Subtotal")
                                    .font(Font.custom("Ysabeau", size: 20))
                                TextField("Subtotal", value: $subtotal, formatter: myNumberFormatter)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: 100)
                                    .font(Font.custom("Ysabeau", size: 20))
                            }
                            .padding(.horizontal)

                            HStack {
                                Text("Tax")
                                    .font(Font.custom("Ysabeau", size: 20))
                                TextField("Tax", value: $tax, formatter: myNumberFormatter)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: 100)
                                    .font(Font.custom("Ysabeau", size: 20))
                            }
                            .padding(.horizontal)

                            HStack {
                                Text("Total")
                                    .font(Font.custom("Ysabeau", size: 20))
                                TextField("Total", value: $total, formatter: myNumberFormatter)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: 100)
                                    .font(Font.custom("Ysabeau", size: 20))
                            }
                            .padding(.horizontal)

                            HStack {
                                Text("Tip")
                                    .font(Font.custom("Ysabeau", size: 20))
                                TextField("Tip", value: $tip, formatter: myNumberFormatter)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: 100)
                                    .font(Font.custom("Ysabeau", size: 20))
                            }
                            HStack {
                                var finalTotalString: String {
                                    myNumberFormatter.string(from: NSNumber(value: total + tip)) ?? ""
                                }

                                Text("Final Total")
                                    .font(Font.custom("Ysabeau", size: 20))
                                Text(finalTotalString)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .frame(width: 100)
                                    .font(Font.custom("Ysabeau", size: 20))
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Checkmark button to navigate to assignTabToFriend
                    NavigationLink(destination: AssignTabToFriend(savedData: saveData(), friends: friends), isActive: $showAssignTabToFriend) {
                        Spacer()
                        Button(action: {
                            showAssignTabToFriend = true
                            let completedSavedData = saveData()
                        }) {
                            Image(systemName: "checkmark") // SF Symbol for checkmark
                                .resizable()
                                .frame(width: 24, height: 24)
                                .foregroundColor(.blue) // Blue color
                                .padding() // Padding around the image
                                .background(Color.blue.opacity(0.1)) // Background color
                                .clipShape(RoundedRectangle(cornerRadius: 10)) // Rounded corners
                        }
                    }.disabled(!isValid)
                        .padding()
                }
                .padding()
            }
        }
    }

    struct AssignTabToFriend: View {
        var savedData: SavedData
        var friends: [Friend]
        @State private var selectedFriend: Friend? = nil
        @State private var showFriendsTabs = false // State to control the navigation to the FriendsTabsView
        @ObservedObject private var selectedItemsManager: SelectedItemsManager

        init(savedData: SavedData, friends: [Friend]) {
            self.savedData = savedData
            self.savedData = savedData
            self.friends = friends
            selectedItemsManager = SelectedItemsManager()
            print("inside asssign tab to friend")
            for friend in friends {
                print("Name: \(friend.tab), Phone: \(friend.phoneNumber ?? "N/A")")
            }
        }

        var body: some View {
            VStack {
                List(friends) { friend in
                    NavigationLink(
                        destination: FriendDetailView(friend: friend, savedData: savedData, selectedItemsManager: selectedItemsManager),
                        tag: friend,
                        selection: $selectedFriend
                    ) {
                        Text(friend.name)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                NavigationLink(
                    destination: FriendsTabsView(friends: friends, savedData: savedData),
                    isActive: $showFriendsTabs
                ) {
                    Button("Done? Get Friend's Tabs Now") {
                        showFriendsTabs = true
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
            }
            .navigationBarTitle("Assign Tab to Friend")
        }
    }

    struct FriendsTabsView: View {
        var friends: [Friend]
        var savedData: SavedData
        @State private var isShowingMessageComposer = false
        @State private var image: UIImage? = nil // Field to attach an image

        var body: some View {
            List {
                ForEach(friends.filter { $0.tab != nil }, id: \.id) { friend in
                    let updatedFriend = updateReceiptImage(for: friend)
                    Section(header: Text(updatedFriend.name).font(.headline)) {
                        ForEach(updatedFriend.tab!.items, id: \.item) { item in
                            VStack(alignment: .leading) {
                                Text(item.item)
                                Text("Quantity: \(String(format: "%.1f", item.quantity))")
                                Text("Price: \(String(format: "%.2f", item.price))")
                            }
                        }
                        if updatedFriend.name == "YOU" {
                            Text("\(updatedFriend.name) owe \(String(format: "%.2f", updatedFriend.tab!.totalPrice))")
                                .font(Font.custom("Ysabeau", size: 28))
                        } else {
                            Text("\(updatedFriend.name) owes \(String(format: "%.2f", updatedFriend.tab!.totalPrice))")
                                .font(Font.custom("Ysabeau", size: 28))
                        }
                    }
                }
            }
            .navigationBarTitle("Your Friends' Tabs")
            .navigationBarItems(trailing: Button("Send Receipts") {
                isShowingMessageComposer = true
            })
            .sheet(isPresented: $isShowingMessageComposer) {
                MessageView(recipients: friends.compactMap { $0.phoneNumber }, message: "Here is your receipt: ", image: image)
            }
        }

        func createReceiptImage(friend: Friend) -> Data? {
            // Make sure the tab is not nil and load the template image
            guard let tab = friend.tab, let templateImage = UIImage(named: "blankReceipt.jpeg") else { return nil }

            // Begin a graphics context
            UIGraphicsBeginImageContext(templateImage.size)

            // Draw the template image
            templateImage.draw(at: .zero)

            // Define attributes for the text
            let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor.black]

            // Draw the friend's name
            let friendName = "Friend: \(friend.name)"
            friendName.draw(at: CGPoint(x: 10, y: 10), withAttributes: attributes)

            // Loop through the items and draw them on the image
            var yOffset: CGFloat = 30
            for item in tab.items {
                let itemText = "Item: \(item.item)"
                let quantityText = "Quantity: \(item.quantity)"
                let priceText = "Price: \(item.price)"

                itemText.draw(at: CGPoint(x: 10, y: yOffset), withAttributes: attributes)
                yOffset += 20
                quantityText.draw(at: CGPoint(x: 10, y: yOffset), withAttributes: attributes)
                yOffset += 20
                priceText.draw(at: CGPoint(x: 10, y: yOffset), withAttributes: attributes)
                yOffset += 30 // Additional spacing between items
            }

            // Create a new UIImage
            guard let newImage = UIGraphicsGetImageFromCurrentImageContext() else {
                UIGraphicsEndImageContext()
                return nil
            }

            // End the graphics context
            UIGraphicsEndImageContext()

            // Convert the UIImage to PNG data
            return newImage.pngData()
        }

        func updateReceiptImage(for friend: Friend) -> Friend {
            var updatedFriend = friend // Make a mutable copy of the friend
            updatedFriend.receiptImageData = createReceiptImage(friend: updatedFriend)
            return updatedFriend
        }
    }

    struct MessageView: UIViewControllerRepresentable {
        @Environment(\.presentationMode) var presentationMode
        var recipients: [String]
        var message: String
        var image: UIImage?

        func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }

        func makeUIViewController(context: Context) -> MFMessageComposeViewController {
            let controller = MFMessageComposeViewController()
            controller.messageComposeDelegate = context.coordinator
            return controller
        }

        func updateUIViewController(_ uiViewController: MFMessageComposeViewController, context: Context) {
            uiViewController.body = message
            uiViewController.recipients = recipients

            // Attach the image if available
            if let imageData = image?.pngData() {
                uiViewController.addAttachmentData(imageData, typeIdentifier: "public.data", filename: "image.png")
            }
        }

        class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
            var parent: MessageView

            init(_ parent: MessageView) {
                self.parent = parent
            }

            func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
                parent.presentationMode.wrappedValue.dismiss()
            }
        }
    }

    class SelectedItemsManager: ObservableObject {
        @Published var selectedItemsByFriend: [Int: Friend] = [:]
    }

    struct FriendDetailView: View {
        var friend: Friend
        var savedData: SavedData // Existing saved data
        @ObservedObject var selectedItemsManager: SelectedItemsManager
        @State private var selectedItems: [Bool] = [] // To track which items are selected
        @State private var tab: Tab // A new tab for the friend

        init(friend: Friend, savedData: SavedData, selectedItemsManager: SelectedItemsManager) {
            self.friend = friend
            self.savedData = savedData
            _selectedItems = State(initialValue: Array(repeating: false, count: savedData.items.count))
            self.selectedItemsManager = selectedItemsManager
            _tab = State(initialValue: Tab(savedData: savedData))
        }

        var body: some View {
            VStack {
                List(savedData.items.indices, id: \.self) { index in
                    if selectedItemsManager.selectedItemsByFriend[index] == nil || selectedItemsManager.selectedItemsByFriend[index] == friend {
                        HStack {
                            Text(savedData.items[index].name)
                            Spacer()
                            Button(action: {
                                if selectedItemsManager.selectedItemsByFriend[index] == friend {
                                    selectedItemsManager.selectedItemsByFriend[index] = nil
                                } else {
                                    selectedItemsManager.selectedItemsByFriend[index] = friend
                                }
                                selectedItems[index].toggle()
                                if selectedItems[index] {
                                    let selectedItem = savedData.items[index]
                                    tab.addItem(item: selectedItem.name, quantity: selectedItem.quantity ?? 0, price: selectedItem.totalPrice)
                                    friend.tab = tab
                                    if let items = friend.tab?.items {
                                        print("Items in Tab:")
                                        for item in items {
                                            print("Item: \(item.item), Quantity: \(item.quantity), Price: \(item.price)")
                                        }
                                    }
                                }
                            }) {
                                Image(systemName: selectedItemsManager.selectedItemsByFriend[index] == friend ? "checkmark.circle.fill" : "circle")
                            }
                        }
                    }
                }
            }
            .navigationBarTitle("Choose Items purchased by \(friend.name)")
        }
    }

    struct PurchasedItem: Identifiable {
        let id = UUID()
        var name: String
        var quantity: Double
        var price: Double
        var purchasedBy: Friend?
    }

    struct AddFriendView: View {
        @Binding var friends: [Friend]

        var body: some View {
            VStack {
                if friends.isEmpty {
                    Text("No Friends")
                        .font(.headline)
                        .padding(.top)

                    NavigationLink("Add Friends", destination: AddFriendFormView(friends: $friends))
                } else {
                    List(friends) { friend in
                        Text(friend.name)
                    }
                }
            }
        }
    }

    struct AddFriendFormView: View {
        @Binding var friends: [Friend]
        @State private var name: String = ""
        @State private var phoneNumber: String = ""
        @Environment(\.presentationMode) var presentationMode

        var body: some View {
            Form {
                Image(systemName: "person.crop.circle")
                    .resizable()
                    .frame(width: 100, height: 100)

                TextField("Name", text: $name)
                TextField("Phone Number (optional)", text: $phoneNumber)
                    .keyboardType(.phonePad)

                Button("Save Friend") {
                    if !name.isEmpty {
                        let newFriend = Friend(name: name, phoneNumber: phoneNumber.isEmpty ? nil : phoneNumber, tab: nil)
                        friends.append(newFriend)
                        presentationMode.wrappedValue.dismiss() // Dismisses the current view and goes back
                    }
                }
            }
        }
    }
}

struct ItemDetail: Codable {
    let item: String
    let quantity: Double
    let price: Double
}

struct SavedData: Codable {
    var items: [Item]
    var subtotal: Double
    var tax: Double
    var total: Double
    var tip: Double
}

class Tab: Codable {
    var items: [ItemDetail] = []
    var savedData: SavedData

    init(savedData: SavedData) {
        self.savedData = savedData
    }

    var totalPrice: Double {
        let friendTotal = items.reduce(0) { $0 + $1.price }
        let subtotal = savedData.subtotal
        let finalTotalAfterTaxAndTips = savedData.total + savedData.tip
        let amountOwedByFriend = (friendTotal / subtotal) * finalTotalAfterTaxAndTips
        return amountOwedByFriend
    }

    func addItem(item: String, quantity: Double, price: Double) {
        items.append(ItemDetail(item: item, quantity: quantity, price: price))
    }

    // Custom encoding method
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(items, forKey: .items)
        try container.encode(savedData, forKey: .savedData) // Encode savedData
    }

    // Custom decoding method
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decode([ItemDetail].self, forKey: .items)
        savedData = try container.decode(SavedData.self, forKey: .savedData) // Decode savedData
    }

    private enum CodingKeys: String, CodingKey {
        case items
        case savedData // Added savedData key
    }
}

class Friend: Identifiable, Codable, Equatable, Hashable {
    var name: String
    var phoneNumber: String?
    var tab: Tab?
    var receiptImageData: Data?

    var receiptImage: UIImage? {
        get {
            if let data = receiptImageData {
                return UIImage(data: data)
            }
            return nil
        }
        set {
            receiptImageData = newValue?.pngData()
        }
    }

    static func == (lhs: Friend, rhs: Friend) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(name: String, phoneNumber: String? = nil, tab: Tab? = nil) {
        self.name = name
        self.phoneNumber = phoneNumber
        self.tab = tab
        receiptImageData = receiptImage?.pngData()
    }
}

class DataManager {
    var friends: [Friend]

    init(friends: [Friend]) {
        self.friends = friends
    }

    func clearTabs() {
        for friend in friends {
            friend.tab = nil
        }
    }

    func getFriends() -> [Friend] {
        return friends
    }
}

struct FriendsListView: View {
    @Binding var friends: [Friend]
    var body: some View {
        List(friends) { friend in
            Text(friend.name)
        }
    }
}

struct Response: Decodable {
    let Items: [Item]
    let Subtotal: Double?
    let Tax: Double?
    let Total: Double?
    let Tip: String?
}

struct Item: Codable {
    var name: String
    var quantity: Double?
    var totalPrice: Double

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case quantity = "Quantity"
        case totalPrice = "Total Price"
    }

    init(name: String, quantity: Double, totalPrice: Double) {
        self.name = name
        self.quantity = quantity
        self.totalPrice = totalPrice
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        totalPrice = try container.decode(Double.self, forKey: .totalPrice)

        // Try to decode quantity as Double
        if let quantityValue = try? container.decode(Double.self, forKey: .quantity) {
            quantity = quantityValue
        } else if let quantityString = try? container.decode(String.self, forKey: .quantity),
                  let quantityValueFromString = Double(quantityString) {
            // If decoding as Double fails, try to decode as String and convert to Double
            quantity = quantityValueFromString
        } else {
            // Default value if both attempts fail
            quantity = 0.0
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
